/* Local-only adapter required by flutter_tesseract_ocr 0.4.31. */
(() => {
  let worker = null;
  let serial = Promise.resolve();
  let rejectCurrent = () => {};
  const base = new URL('ocr/', document.baseURI);
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
        await current.setParameters(parameters);
        const input = meter_enhance ? await enhance(source) : source;
        const result = await current.recognize(input);
        return result.data.text;
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
