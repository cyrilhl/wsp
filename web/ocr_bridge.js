/* Local-only adapter required by flutter_tesseract_ocr 0.4.31. */
(() => {
  let worker = null;
  let serial = Promise.resolve();
  let rejectCurrent = () => {};
  const base = new URL('ocr/', document.baseURI);
  const isNumber = text => /^-?\d+(?:\.\d+)?$/.test(text.trim());
  // Locate with unrestricted text: a numeric whitelist can turn labels into digits.
  function readingRegion(words = []) {
    const candidates = words.filter(word =>
      /^[\-−–—]*\d+(?:[.,]\d+)?%?$/.test(word.text.trim()) &&
      word.bbox && word.bbox.x1 > word.bbox.x0 && word.bbox.y1 > word.bbox.y0);
    const rows = [];
    for (const word of candidates.sort((a, b) => a.bbox.x0 - b.bbox.x0)) {
      const box = word.bbox;
      const height = box.y1 - box.y0;
      const row = rows.find(row => {
        const overlap = Math.min(row.y1, box.y1) - Math.max(row.y0, box.y0);
        return overlap >= .6 * Math.max(row.height, height) &&
          Math.min(row.height, height) >= .65 * Math.max(row.height, height) &&
          box.x0 - row.x1 <= .8 * Math.max(row.height, height);
      });
      if (row) {
        row.x1 = Math.max(row.x1, box.x1);
        row.y0 = Math.min(row.y0, box.y0);
        row.y1 = Math.max(row.y1, box.y1);
        row.height = Math.max(row.height, height);
        row.negative ||= /^[\-−–—]/.test(word.text.trim());
      } else rows.push({...box, height, negative: /^[\-−–—]/.test(word.text.trim())});
    }
    rows.sort((a, b) => b.height - a.height);
    if (!rows.length) return null;
    // Size is a prior, not proof. Do not choose between similarly prominent rows.
    if (rows[1] && rows[1].height >= rows[0].height * .8) return {ambiguous: true};
    const row = {...rows[0]};
    // Keep detached punctuation near the digits, even though it is much smaller.
    for (const word of words) {
      if (!/^[.\-−–—]+$/.test(word.text.trim()) || !word.bbox) continue;
      const box = word.bbox;
      if (box.x1 >= row.x0 - row.height * .8 && box.x0 <= row.x1 + row.height * .5 &&
          box.y1 >= row.y0 && box.y0 <= row.y1 + row.height * .15) {
        row.x0 = Math.min(row.x0, box.x0);
        row.x1 = Math.max(row.x1, box.x1);
        row.y0 = Math.min(row.y0, box.y0);
        row.y1 = Math.max(row.y1, box.y1);
        if (/^[\-−–—]+$/.test(word.text.trim())) row.negative = true;
      }
    }
    return row;
  }
  async function cropReading(source, region) {
    const image = new Image();
    image.src = source;
    await image.decode();
    // Preserve small, unrecognized punctuation as pixels; do not filter components.
    const margin = Math.max(4, region.height * .35);
    const left = Math.max(0, Math.floor(region.x0 - margin));
    const top = Math.max(0, Math.floor(region.y0 - margin));
    const width = Math.min(image.naturalWidth, Math.ceil(region.x1 + margin)) - left;
    const height = Math.min(image.naturalHeight, Math.ceil(region.y1 + margin)) - top;
    const scale = Math.min(3, Math.max(1, 64 / region.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(width * scale) + 20;
    canvas.height = Math.ceil(height * scale) + 20;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = 'white';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(image, left, top, width, height, 10, 10, canvas.width - 20, canvas.height - 20);
    return canvas.toDataURL('image/png');
  }
  async function enhance(source) {
    const image = new Image();
    image.src = source;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    const ctx = canvas.getContext('2d', {willReadFrequently: true});
    ctx.drawImage(image, 0, 0);
    const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height);
    for (let i = 0; i < pixels.data.length; i += 4) {
      const gray = .299 * pixels.data[i] + .587 * pixels.data[i + 1] + .114 * pixels.data[i + 2];
      const value = Math.max(0, Math.min(255, (gray - 128) * 1.7 + 128));
      pixels.data[i] = pixels.data[i + 1] = pixels.data[i + 2] = value;
    }
    ctx.putImageData(pixels, 0, 0);
    return canvas.toDataURL('image/png');
  }
  window._extractText = (source, config) => {
    const run = async () => {
      let timedOut = false;
      let timer;
      let failWorker;
      const failure = new Promise((_, reject) => { failWorker = reject; });
      rejectCurrent = failWorker;
      const work = async () => {
        let current = worker;
        if (!current) {
          const created = await Tesseract.createWorker({
            workerPath: new URL('worker.min.js', base).href,
            corePath: new URL('tesseract-core.wasm.js', base).href,
            langPath: base.href.replace(/\/$/, ''),
            workerBlobURL: false,
            // Service worker owns the language cache; avoid a second IDB cache.
            cacheMethod: 'none',
            errorHandler: error => rejectCurrent(new Error(String(error))),
          });
          if (timedOut) { await created.terminate(); throw new Error('OCR initialization timed out.'); }
          worker = current = created;
          await current.loadLanguage('eng');
          await current.initialize('eng');
        }
        const {meter_enhance, ...parameters} = config.args || {};
        await current.setParameters({
          ...parameters, tessedit_pageseg_mode: '11', tessedit_char_whitelist: '',
        });
        const located = await current.recognize(source);
        const region = readingRegion(located.data.words);
        if (region?.ambiguous) return '';
        const input = region ? await cropReading(source, region) : source;
        await current.setParameters({
          tessedit_pageseg_mode: '7', tessedit_char_whitelist: '0123456789.-',
          ...parameters,
          // Raw-line mode avoids treating a leading minus as a list marker.
          ...(region?.negative ? {tessedit_pageseg_mode: '13'} : {}),
        });
        const original = (await current.recognize(input)).data.text;
        const preserveSign = text => region?.negative && !text.trim().startsWith('-') ? '' : text;
        if (!meter_enhance) return preserveSign(original);
        const enhanced = (await current.recognize(await enhance(input))).data.text;
        // Two plausible but different readings require human review.
        if (isNumber(original) && isNumber(enhanced) && original.trim() !== enhanced.trim()) return '';
        return preserveSign(isNumber(original) ? original : enhanced);
      };
      try {
        return await Promise.race([work(), failure, new Promise((_, reject) => {
          timer = setTimeout(() => { timedOut = true; reject(new Error('OCR timed out after 60 seconds.')); }, 60000);
        })]);
      } catch (error) {
        timedOut = true;
        const failed = worker;
        worker = null;
        if (failed) await failed.terminate();
        throw error;
      } finally { clearTimeout(timer); }
    };
    const result = serial.then(run, run);
    serial = result.catch(() => {});
    return result;
  };
})();
