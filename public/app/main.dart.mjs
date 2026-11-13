// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      AC: Function.prototype.call.bind(DataView.prototype.setInt16),
      AD: x0 => x0.height,
      AE: (x0,x1) => x0.observe(x1),
      AF: x0 => x0.wheelDeltaY,
      AG: x0 => x0.v8BreakIterator,
      AH: x0 => x0.selectionDirection,
      AI: () => Date.now(),
      AJ: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      AK: (x0,x1) => x0.createElement(x1),
      AL: x0 => x0.isComposing,
      AM: x0 => x0.hostname,
      AN: x0 => x0.message,
      AO: x0 => x0.onLine,
      AP: x0 => globalThis.firebase_firestore.Bytes.fromUint8Array(x0),
      AQ: x0 => x0.length,
      B: s => printToConsole(s),
      BB: b => !!b,
      BC: Function.prototype.call.bind(DataView.prototype.setUint16),
      BD: x0 => x0.width,
      BE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      BF: x0 => x0.wheelDeltaX,
      BG: () => globalThis.Intl,
      BH: x0 => x0.selectionStart,
      BI: x0 => new WeakRef(x0),
      BJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      BK: () => globalThis.document,
      BL: x0 => x0.code,
      BM: x0 => x0.location,
      BN: x0 => x0.code,
      BO: x0 => globalThis.firebase_firestore.memoryLocalCache(x0),
      BP: (x0,x1,x2) => globalThis.firebase_firestore.initializeFirestore(x0,x1,x2),
      BQ: x0 => x0.getReader(),
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      CC: Function.prototype.call.bind(DataView.prototype.setUint8),
      CD: x0 => x0.screen,
      CE: x0 => new ResizeObserver(x0),
      CF: x0 => x0.key,
      CG: (x0,x1) => x0.segment(x1),
      CH: x0 => x0.selectionEnd,
      CI: x0 => x0.deref(),
      CJ: () => new XMLHttpRequest(),
      CK: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      CL: x0 => x0.repeat,
      CM: (x0,x1,x2) => ({errorMap: x0,persistence: x1,popupRedirectResolver: x2}),
      CN: x0 => x0.idToken,
      CO: x0 => ({cacheSizeBytes: x0}),
      CP: (x0,x1) => globalThis.firebase_firestore.getFirestore(x0,x1),
      CQ: x0 => x0.value,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: (x0,x1) => x0.focus(x1),
      DC: Function.prototype.call.bind(DataView.prototype.setInt8),
      DD: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      DE: (x0,x1) => x0.getPropertyValue(x1),
      DF: x0 => x0.identifier,
      DG: x0 => x0.index,
      DH: x0 => x0.keyCode,
      DI: () => globalThis.WeakRef,
      DJ: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      DK: x0 => x0.abort(),
      DL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      DM: (x0,x1) => globalThis.firebase_auth.initializeAuth(x0,x1),
      DN: x0 => x0.secret,
      DO: x0 => globalThis.firebase_firestore.persistentLocalCache(x0),
      DP: (x0,x1) => x0.delete(x1),
      DQ: x0 => x0.done,
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: () => ({}),
      EC: Function.prototype.call.bind(DataView.prototype.getInt8),
      ED: x0 => x0.tabIndex,
      EE: x0 => globalThis.parseFloat(x0),
      EF: x0 => x0.touches,
      EG: x0 => x0.next(),
      EH: (x0,x1) => x0.scrollIntoView(x1),
      EI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      EJ: x0 => x0.send(),
      EK: () => new AbortController(),
      EL: x0 => x0.userAgent,
      EM: () => globalThis.firebase_auth.browserPopupRedirectResolver,
      EN: x0 => x0.accessToken,
      EO: (x0,x1,x2,x3) => ({ignoreUndefinedProperties: x0,experimentalForceLongPolling: x1,experimentalAutoDetectLongPolling: x2,localCache: x3}),
      EP: (x0,x1,x2,x3) => x0.set(x1,x2,x3),
      EQ: x0 => x0.read(),
      F: () => new Error().stack,
      FB: (o, p, v) => o[p] = v,
      FC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      FD: (x0,x1) => x0.contains(x1),
      FE: (x0,x1) => x0.getComputedStyle(x1),
      FF: x0 => x0.pressure,
      FG: x0 => x0.value,
      FH: x0 => x0.multiViewEnabled,
      FI: (a, s, e) => a.slice(s, e),
      FJ: x0 => x0.type,
      FK: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      FL: (x0,x1,x2) => x0.setItem(x1,x2),
      FM: () => globalThis.firebase_auth.debugErrorMap,
      FN: x0 => x0.signInMethod,
      FO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      FP: (x0,x1,x2) => x0.set(x1,x2),
      FQ: x0 => x0.body,
      G: s => JSON.stringify(s),
      GB: () => [],
      GC: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      GD: x0 => x0.activeElement,
      GE: x0 => x0.documentElement,
      GF: x0 => x0.tiltY,
      GG: x0 => x0.done,
      GH: (x0,x1) => x0.replaceWith(x1),
      GI: x0 => x0.message,
      GJ: x0 => x0.response,
      GK: (x0,x1) => globalThis.fetch(x0,x1),
      GL: x0 => x0.localStorage,
      GM: () => globalThis.firebase_auth.browserSessionPersistence,
      GN: x0 => x0.providerId,
      GO: x0 => ({maxAttempts: x0}),
      GP: x0 => x0.commit(),
      GQ: (x0,x1) => new OffscreenCanvas(x0,x1),
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: (a, i) => a.push(i),
      HC: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      HD: x0 => x0.parentNode,
      HE: x0 => x0.computedStyleMap(),
      HF: x0 => x0.tiltX,
      HG: (o, m, a) => o[m].apply(o, a),
      HH: (x0,x1) => { x0.type = x1 },
      HI: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      HJ: (x0,x1) => { x0.responseType = x1 },
      HK: (x0,x1) => x0.get(x1),
      HL: (x0,x1) => x0.getItem(x1),
      HM: () => globalThis.firebase_auth.browserLocalPersistence,
      HN: x0 => x0.reload(),
      HO: (x0,x1,x2) => globalThis.firebase_firestore.runTransaction(x0,x1,x2),
      HP: x0 => globalThis.firebase_firestore.writeBatch(x0),
      HQ: x0 => x0.assetBase,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: x0 => new Int8Array(x0),
      IC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      ID: x0 => x0.tagName,
      IE: (x0,x1) => x0.get(x1),
      IF: x0 => x0.pointerType,
      IG: x0 => x0.iterator,
      IH: (x0,x1) => { x0.className = x1 },
      II: (x0,x1) => x0.revokeObjectURL(x1),
      IJ: x0 => x0.vendor,
      IK: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      IL: (x0,x1) => x0.key(x1),
      IM: () => globalThis.firebase_auth.indexedDBLocalPersistence,
      IN: (x0,x1) => x0.getIdToken(x1),
      IO: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      IP: (x0,x1) => ({includeMetadataChanges: x0,source: x1}),
      IQ: x0 => x0.loader,
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      JC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      JD: x0 => x0.target,
      JE: (o, p) => p in o,
      JF: x0 => x0.pointerId,
      JG: () => globalThis.Symbol,
      JH: (x0,x1) => { x0.tabIndex = x1 },
      JI: (x0,x1) => { x0.src = x1 },
      JJ: x0 => x0.navigator,
      JK: (x0,x1) => x0.forEach(x1),
      JL: x0 => x0.length,
      JM: x0 => x0.name,
      JN: (x0,x1) => ({displayName: x0,photoURL: x1}),
      JO: (o,s,v) => o[s] = v,
      JP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      JQ: () => globalThis._flutter,
      K: o => o,
      KB: x0 => new Uint8Array(x0),
      KC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      KD: x0 => x0.clientY,
      KE: (x0,x1) => { x0.textContent = x1 },
      KF: x0 => x0.getCoalescedEvents(),
      KG: (x0,x1) => new Intl.Segmenter(x0,x1),
      KH: (x0,x1) => { x0.name = x1 },
      KI: (x0,x1,x2,x3,x4) => globalThis.createImageBitmap(x0,x1,x2,x3,x4),
      KJ: () => globalThis.window,
      KK: x0 => x0.name,
      KL: (x0,x1) => ({files: x0,title: x1}),
      KM: (o) => {
        const typeofValue = typeof o;
        return (typeofValue === 'object') ||
            typeofValue === 'function';
      },
      KN: x0 => ({displayName: x0}),
      KO: () => Symbol("jsBoxedDartObjectProperty"),
      KP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      L: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      LB: x0 => new Uint8ClampedArray(x0),
      LC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      LD: x0 => x0.clientX,
      LE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      LF: (x0,x1) => x0.getModifierState(x1),
      LG: x0 => x0.Segmenter,
      LH: (x0,x1) => { x0.placeholder = x1 },
      LI: x0 => x0.naturalHeight,
      LJ: (x0,x1) => x0.getRandomValues(x1),
      LK: x0 => x0.statusText,
      LL: x0 => ({files: x0}),
      LM: (x0,x1,x2,x3,x4,x5,x6,x7) => ({apiKey: x0,authDomain: x1,databaseURL: x2,projectId: x3,storageBucket: x4,messagingSenderId: x5,measurementId: x6,appId: x7}),
      LN: x0 => ({photoURL: x0}),
      LO: (x0,x1) => x0.delete(x1),
      LP: (x0,x1,x2,x3) => globalThis.firebase_firestore.onSnapshot(x0,x1,x2,x3),
      M: x0 => x0.index,
      MB: x0 => new Int16Array(x0),
      MC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      MD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      ME: x0 => x0.matches,
      MF: s => s.trimLeft(),
      MG: x0 => x0.buffer,
      MH: (x0,x1) => { x0.autocomplete = x1 },
      MI: x0 => x0.naturalWidth,
      MJ: () => globalThis.crypto,
      MK: x0 => x0.url,
      ML: (x0,x1) => x0.canShare(x1),
      MM: (x0,x1) => globalThis.firebase_core.initializeApp(x0,x1),
      MN: (x0,x1) => globalThis.firebase_auth.updateProfile(x0,x1),
      MO: (x0,x1) => globalThis.firebase_firestore.doc(x0,x1),
      MP: (x0,x1,x2) => globalThis.firebase_firestore.onSnapshot(x0,x1,x2),
      N: o => String(o),
      NB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      NC: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      ND: x0 => x0.getBoundingClientRect(),
      NE: (x0,x1) => x0.matchMedia(x1),
      NF: s => s.toUpperCase(),
      NG: x0 => x0.wasmMemory,
      NH: (x0,x1) => { x0.name = x1 },
      NI: x0 => x0.decode(),
      NJ: l => new DataView(new ArrayBuffer(l)),
      NK: x0 => x0.status,
      NL: (x0,x1) => x0.share(x1),
      NM: x0 => x0.storageBucket,
      NN: x0 => x0.providerId,
      NO: x0 => ({serverTimestamps: x0}),
      NP: x0 => globalThis.firebase_firestore.deleteDoc(x0),
      O: o => o === undefined,
      OB: x0 => new Uint16Array(x0),
      OC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      OD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      OE: x0 => x0.matches,
      OF: x0 => x0.pop(),
      OG: () => globalThis.window._flutter_skwasmInstance,
      OH: (x0,x1) => { x0.placeholder = x1 },
      OI: (x0,x1) => { x0.decoding = x1 },
      OJ: (a, i) => a.splice(i, 1)[0],
      OK: x0 => x0.getReader(),
      OL: x0 => x0.message,
      OM: x0 => x0.databaseURL,
      ON: x0 => x0.providerData,
      OO: x0 => x0.fromCache,
      OP: x0 => globalThis.firebase_firestore.getDoc(x0),
      P: (x0,x1) => x0.exec(x1),
      PB: x0 => new Int32Array(x0),
      PC: (x0,x1) => x0.querySelector(x1),
      PD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      PE: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      PF: x0 => x0.flags,
      PG: () => new TextDecoder(),
      PH: (x0,x1) => { x0.action = x1 },
      PI: (x0,x1) => { x0.crossOrigin = x1 },
      PJ: x0 => x0.decode(),
      PK: x0 => x0.read(),
      PL: x0 => x0.remove(),
      PM: x0 => x0.apiKey,
      PN: x0 => x0.tenantId,
      PO: x0 => x0.hasPendingWrites,
      PP: x0 => globalThis.firebase_firestore.getDocFromServer(x0),
      Q: (x0,x1) => { x0.lastIndex = x1 },
      QB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      QC: (x0,x1) => x0.item(x1),
      QD: Date.now,
      QE: f => f.dartFunction,
      QF: (a, s) => a.join(s),
      QG: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      QH: (x0,x1) => { x0.method = x1 },
      QI: (x0,x1) => x0.createObjectURL(x1),
      QJ: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      QK: x0 => x0.value,
      QL: x0 => x0.body,
      QM: x0 => x0.options,
      QN: x0 => x0.refreshToken,
      QO: x0 => x0.metadata,
      QP: x0 => globalThis.firebase_firestore.getDocFromCache(x0),
      R: o => o,
      RB: x0 => new Uint32Array(x0),
      RC: x0 => x0.length,
      RD: (handle) => clearTimeout(handle),
      RE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      RF: (x0,x1) => x0.error(x1),
      RG: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      RH: (x0,x1) => { x0.noValidate = x1 },
      RI: x0 => x0.URL,
      RJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      RK: x0 => x0.done,
      RL: (x0,x1) => { x0.download = x1 },
      RM: () => globalThis.firebase_core.SDK_VERSION,
      RN: x0 => x0.photoURL,
      RO: x0 => x0.toArray(),
      RP: x0 => x0.source,
      S: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      SB: x0 => new Float32Array(x0),
      SC: (x0,x1) => x0.querySelectorAll(x1),
      SD: (x0,x1) => x0.closest(x1),
      SE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SF: () => globalThis.console,
      SG: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      SH: (x0,x1) => x0.removeAttribute(x1),
      SI: x0 => new Blob(x0),
      SJ: (x0,x1,x2) => x0.addEventListener(x1,x2),
      SK: x0 => x0.cancel(),
      SL: (x0,x1) => { x0.href = x1 },
      SM: (x0,x1,x2) => globalThis.firebase_core.registerVersion(x0,x1,x2),
      SN: x0 => x0.phoneNumber,
      SO: x0 => x0.toUint8Array(),
      SP: x0 => ({source: x0}),
      T: o => o instanceof RegExp,
      TB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      TC: (x0,x1) => x0.getAttribute(x1),
      TD: x0 => x0.bottom,
      TE: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      TF: s => s.trimRight(),
      TG: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      TH: x0 => x0.isConnected,
      TI: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      TJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      TK: x0 => x0.body,
      TL: () => ({}),
      TM: (x0,x1) => x0.debug(x1),
      TN: x0 => x0.lastSignInTime,
      TO: () => globalThis.firebase_firestore.Bytes,
      TP: (x0,x1,x2) => globalThis.firebase_firestore.setDoc(x0,x1,x2),
      U: (string, times) => string.repeat(times),
      UB: x0 => new Float64Array(x0),
      UC: x0 => x0.remove(),
      UD: x0 => x0.top,
      UE: (o, i) => o[i],
      UF: x0 => x0.blur(),
      UG: x0 => x0.history,
      UH: x0 => x0.click(),
      UI: x0 => new window.ImageDecoder(x0),
      UJ: x0 => x0.send(),
      UK: x0 => x0.headers,
      UL: (x0,x1,x2) => new File(x0,x1,x2),
      UM: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      UN: x0 => x0.creationTime,
      UO: () => globalThis.firebase_firestore.VectorValue,
      UP: (x0,x1) => globalThis.firebase_firestore.setDoc(x0,x1),
      V: o => o,
      VB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      VC: (x0,x1) => x0.appendChild(x1),
      VD: x0 => x0.right,
      VE: o => o.length,
      VF: x0 => x0.button,
      VG: x0 => x0.search,
      VH: (x0,x1) => x0.getElementsByClassName(x1),
      VI: x0 => x0.name,
      VJ: x0 => x0.status,
      VK: x0 => x0.signal,
      VL: (x0,x1) => { x0.type = x1 },
      VM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      VN: x0 => x0.metadata,
      VO: x0 => x0.longitude,
      VP: () => globalThis.firebase_firestore.count(),
      W: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      WB: x0 => new ArrayBuffer(x0),
      WC: (x0,x1) => x0.append(x1),
      WD: x0 => x0.left,
      WE: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      WF: x0 => x0.innerHeight,
      WG: x0 => x0.location,
      WH: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      WI: x0 => x0.repetitionCount,
      WJ: x0 => x0.response,
      WK: (x0,x1,x2) => x0.insertBefore(x1,x2),
      WL: x0 => x0.code,
      WM: (x0,x1) => ({createScript: x0,createScriptURL: x1}),
      WN: x0 => x0.isAnonymous,
      WO: x0 => x0.latitude,
      WP: x0 => globalThis.firebase_firestore.sum(x0),
      X: x0 => x0.dotAll,
      XB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      XC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      XD: x0 => x0.clientY,
      XE: x0 => x0.language,
      XF: x0 => x0.innerWidth,
      XG: x0 => x0.pathname,
      XH: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      XI: x0 => x0.frameCount,
      XJ: (x0,x1,x2) => x0.setRequestHeader(x1,x2),
      XK: x0 => x0.id,
      XL: (x0,x1) => globalThis.firebase_storage.ref(x0,x1),
      XM: (x0,x1,x2) => x0.createPolicy(x1,x2),
      XN: x0 => x0.emailVerified,
      XO: () => globalThis.firebase_firestore.GeoPoint,
      XP: x0 => globalThis.firebase_firestore.average(x0),
      Y: x0 => x0.unicode,
      YB: (x0,x1,x2) => new DataView(x0,x1,x2),
      YC: x0 => x0.style,
      YD: x0 => x0.clientX,
      YE: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      YF: x0 => x0.height,
      YG: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      YH: (x0,x1) => x0.dispatchEvent(x1),
      YI: x0 => x0.selectedTrack,
      YJ: (x0,x1) => { x0.responseType = x1 },
      YK: x0 => x0.offsetHeight,
      YL: (x0,x1) => globalThis.firebase_storage.getStorage(x0,x1),
      YM: (x0,x1) => x0.createScriptURL(x1),
      YN: x0 => x0.email,
      YO: (x0,x1) => x0.data(x1),
      YP: (x0,x1) => globalThis.firebase_firestore.getAggregateFromServer(x0,x1),
      Z: x0 => x0.ignoreCase,
      ZB: (o, p) => o[p],
      ZC: x0 => x0.debugShowSemanticsNodes,
      ZD: x0 => x0.changedTouches,
      ZE: () => globalThis.window.FinalizationRegistry,
      ZF: x0 => x0.width,
      ZG: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      ZH: (x0,x1) => x0.createEvent(x1),
      ZI: x0 => x0.completed,
      ZJ: () => new XMLHttpRequest(),
      ZK: x0 => x0.offsetWidth,
      ZL: x0 => globalThis.firebase_storage.getStorage(x0),
      ZM: (x0,x1,x2) => x0.createScript(x1,x2),
      ZN: x0 => x0.displayName,
      ZO: x0 => x0.nanoseconds,
      ZP: x0 => x0.data(),
      a: x0 => x0.multiline,
      aB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      aC: (x0,x1) => x0.warn(x1),
      aD: x0 => x0.offsetY,
      aE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      aF: x0 => x0.clientHeight,
      aG: o => Object.keys(o),
      aH: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      aI: x0 => x0.ready,
      aJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      aK: x0 => x0.stopPropagation(),
      aL: x0 => x0.name,
      aM: (x0,x1) => x0.appendChild(x1),
      aN: x0 => globalThis.firebase_auth.multiFactor(x0),
      aO: x0 => x0.seconds,
      aP: (x0,x1,x2) => globalThis.firebase_firestore.where(x0,x1,x2),
      b: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      bB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      bC: x0 => x0.console,
      bD: x0 => x0.offsetX,
      bE: x0 => new window.FinalizationRegistry(x0),
      bF: x0 => x0.clientWidth,
      bG: x0 => x0.state,
      bH: x0 => x0.readText(),
      bI: x0 => x0.tracks,
      bJ: (x0,x1,x2) => x0.addEventListener(x1,x2),
      bK: x0 => x0.disabled,
      bL: x0 => globalThis.firebase_core.getApp(x0),
      bM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      bN: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      bO: () => globalThis.firebase_firestore.Timestamp,
      bP: (x0,x1) => globalThis.firebase_firestore.query(x0,x1),
      c: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      cB: o => o.byteOffset,
      cC: () => globalThis.window,
      cD: x0 => x0.type,
      cE: (x0,x1) => x0.unregister(x1),
      cF: (x0,x1) => { x0.content = x1 },
      cG: x0 => x0.hash,
      cH: x0 => x0.clipboard,
      cI: x0 => x0.close(),
      cJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      cK: (x0,x1) => { x0.min = x1 },
      cL: () => globalThis.firebase_core.getApp(),
      cM: (o, p) => delete o[p],
      cN: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      cO: () => globalThis.firebase_firestore.DocumentReference,
      cP: () => globalThis.firebase_firestore.and,
      d: (x0,x1) => x0.didCreateEngineInitializer(x1),
      dB: o => o.buffer,
      dC: (o, c) => o instanceof c,
      dD: x0 => x0.maxTouchPoints,
      dE: (x0,x1) => x0.contains(x1),
      dF: (x0,x1) => { x0.name = x1 },
      dG: x0 => x0.state,
      dH: (x0,x1) => x0.writeText(x1),
      dI: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      dJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      dK: (x0,x1) => { x0.max = x1 },
      dL: x0 => x0.state,
      dM: (o, p, v) => o[p] = v,
      dN: (x0,x1,x2) => x0.onIdTokenChanged(x1,x2),
      dO: x0 => x0.path,
      dP: () => globalThis.firebase_firestore.or,
      e: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      eB: Function.prototype.call.bind(DataView.prototype.getUint8),
      eC: (x0,x1) => x0[x1],
      eD: x0 => x0.platform,
      eE: (s) => +s,
      eF: x0 => x0.head,
      eG: (x0,x1) => x0.go(x1),
      eH: x0 => x0.unlock(),
      eI: (x0,x1) => x0.decode(x1),
      eJ: (x0,x1) => x0.removeChild(x1),
      eK: (x0,x1) => { x0.disabled = x1 },
      eL: x0 => x0.snapshot,
      eM: (x0,x1) => { x0.text = x1 },
      eN: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      eO: x0 => x0.ref,
      eP: x0 => globalThis.firebase_firestore.limitToLast(x0),
      f: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      fB: (b, o) => new DataView(b, o),
      fC: x0 => x0.length,
      fD: x0 => x0.body,
      fE: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      fF: (x0,x1) => x0.removeChild(x1),
      fG: x0 => x0.parentElement,
      fH: (x0,x1) => x0.lock(x1),
      fI: x0 => x0.displayHeight,
      fJ: x0 => x0.click(),
      fK: (x0,x1) => { x0.scrollLeft = x1 },
      fL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fM: x0 => x0.head,
      fN: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fO: (x0,x1) => x0.get(x1),
      fP: x0 => globalThis.firebase_firestore.limit(x0),
      g: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      gB: (b, o, l) => new DataView(b, o, l),
      gC: (string, token) => string.split(token),
      gD: () => globalThis.document,
      gE: s => s.trim(),
      gF: x0 => x0.firstChild,
      gG: (x0,x1) => x0.querySelectorAll(x1),
      gH: x0 => x0.orientation,
      gI: x0 => x0.displayWidth,
      gJ: (o, a) => o + a,
      gK: (x0,x1) => { x0.spellcheck = x1 },
      gL: (x0,x1) => x0.then(x1),
      gM: (x0,x1) => { x0.text = x1 },
      gN: (x0,x1) => globalThis.firebase_auth.setPersistence(x0,x1),
      gO: (x0,x1,x2,x3) => x0.set(x1,x2,x3),
      gP: () => globalThis.firebase_firestore.endBefore,
      h: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      hB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      hC: o => o instanceof Array,
      hD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      hE: x0 => x0.classList,
      hF: x0 => x0.viewConstraints,
      hG: (d, digits) => d.toFixed(digits),
      hH: (x0,x1) => x0.querySelector(x1),
      hI: x0 => x0.duration,
      hJ: x0 => x0.children,
      hK: (x0,x1) => { x0.disabled = x1 },
      hL: (x0,x1,x2) => globalThis.firebase_storage.uploadBytesResumable(x0,x1,x2),
      hM: x0 => x0.trustedTypes,
      hN: () => globalThis.firebase_auth.inMemoryPersistence,
      hO: (x0,x1,x2) => x0.set(x1,x2),
      hP: () => globalThis.firebase_firestore.endAt,
      i: x0 => new Promise(x0),
      iB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      iC: (a, i) => a[i],
      iD: x0 => x0.hasFocus(),
      iE: x0 => x0.preventDefault(),
      iF: x0 => x0.hostElement,
      iG: x0 => x0.maxHeight,
      iH: (x0,x1) => { x0.title = x1 },
      iI: x0 => x0.image,
      iJ: x0 => x0.firstChild,
      iK: (x0,x1) => x0.transferFromImageBitmap(x1),
      iL: () => ({}),
      iM: () => globalThis.console,
      iN: x0 => x0.user,
      iO: (x0,x1) => new firebase_firestore.Timestamp(x0,x1),
      iP: () => globalThis.firebase_firestore.startAfter,
      j: (x0,x1,x2) => x0.call(x1,x2),
      jB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      jC: a => a.length,
      jD: x0 => x0.relatedTarget,
      jE: x0 => x0.parent,
      jF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      jG: x0 => x0.maxWidth,
      jH: (x0,x1) => x0.vibrate(x1),
      jI: () => globalThis.window.ImageDecoder,
      jJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      jK: (x0,x1) => x0.getContext(x1),
      jL: (x0,x1) => { x0.customMetadata = x1 },
      jM: x0 => x0.trustedTypes,
      jN: x0 => globalThis.firebase_auth.OAuthProvider.credentialFromResult(x0),
      jO: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      jP: () => globalThis.firebase_firestore.startAt,
      k: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      kB: (t, s) => t.set(s),
      kC: (x0,x1) => x0.test(x1),
      kD: x0 => x0.shiftKey,
      kE: x0 => x0.timeStamp,
      kF: x0 => ({runApp: x0}),
      kG: x0 => x0.minHeight,
      kH: x0 => x0.arrayBuffer(),
      kI: x0 => x0.naturalHeight,
      kJ: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      kK: (x0,x1) => { x0.height = x1 },
      kL: (x0,x1) => { x0.contentType = x1 },
      kM: (x0,x1) => { x0.crossOrigin = x1 },
      kN: x0 => x0.username,
      kO: () => globalThis.firebase_firestore.deleteField(),
      kP: (x0,x1) => globalThis.firebase_firestore.orderBy(x0,x1),
      l: x0 => new Array(x0),
      lB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      lC: x0 => x0.userAgent,
      lD: (decoder, codeUnits) => decoder.decode(codeUnits),
      lE: (x0,x1) => x0.hasAttribute(x1),
      lF: () => typeof dartUseDateNowForTicks !== "undefined",
      lG: x0 => x0.minWidth,
      lH: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      lI: x0 => x0.naturalWidth,
      lJ: (x0,x1) => x0.item(x1),
      lK: (x0,x1) => { x0.width = x1 },
      lL: x0 => globalThis.firebase_storage.deleteObject(x0),
      lM: (x0,x1) => { x0.type = x1 },
      lN: x0 => x0.providerId,
      lO: () => globalThis.firebase_firestore.serverTimestamp(),
      lP: x0 => x0.metadata,
      m: o => [o],
      mB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      mC: x0 => x0.navigator,
      mD: () => new TextDecoder("utf-8", {fatal: true}),
      mE: x0 => x0.buttons,
      mF: () => Date.now(),
      mG: (x0,x1) => x0.removeProperty(x1),
      mH: x0 => x0.status,
      mI: (x0,x1) => x0.createElement(x1),
      mJ: x0 => ({type: x0}),
      mK: x0 => x0.height,
      mL: x0 => globalThis.firebase_storage.getDownloadURL(x0),
      mM: () => globalThis.firebase_core.getApps(),
      mN: x0 => x0.profile,
      mO: x0 => ({merge: x0}),
      mP: x0 => x0.doc,
      n: (o0, o1) => [o0, o1],
      nB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      nC: Function.prototype.call.bind(String.prototype.toLowerCase),
      nD: () => new TextDecoder("utf-8", {fatal: false}),
      nE: x0 => x0.ctrlKey,
      nF: () => 1000 * performance.now(),
      nG: (x0,x1) => x0.add(x1),
      nH: (x0,x1) => x0.fetch(x1),
      nI: (x0,x1) => { x0.pointerEvents = x1 },
      nJ: (x0,x1) => new Blob(x0,x1),
      nK: x0 => x0.width,
      nL: x0 => x0.measurementId,
      nM: x0 => globalThis.firebase_auth.OAuthProvider.credentialFromError(x0),
      nN: x0 => x0.isNewUser,
      nO: x0 => new firebase_firestore.FieldPath(x0),
      nP: x0 => x0.newIndex,
      o: (o0, o1, o2) => [o0, o1, o2],
      oB: Function.prototype.call.bind(DataView.prototype.getUint32),
      oC: Object.is,
      oD: (a, i, v) => a[i] = v,
      oE: x0 => x0.y,
      oF: (x0,x1) => x0.requestAnimationFrame(x1),
      oG: x0 => x0.data,
      oH: x0 => x0.content,
      oI: (x0,x1) => { x0.height = x1 },
      oJ: x0 => globalThis.URL.createObjectURL(x0),
      oK: x0 => x0.rasterEndMilliseconds,
      oL: x0 => x0.appId,
      oM: x0 => x0.session,
      oN: x0 => globalThis.firebase_auth.getAdditionalUserInfo(x0),
      oO: (x0,x1) => new firebase_firestore.FieldPath(x0,x1),
      oP: x0 => x0.oldIndex,
      p: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      pB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      pC: x0 => x0.vendor,
      pD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      pE: x0 => x0.x,
      pF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      pG: (x0,x1) => { x0.scrollTop = x1 },
      pH: x0 => x0.document,
      pI: (x0,x1) => { x0.width = x1 },
      pJ: x0 => x0.size,
      pK: x0 => x0.rasterStartMilliseconds,
      pL: x0 => x0.messagingSenderId,
      pM: x0 => x0.phoneNumber,
      pN: (x0,x1) => globalThis.firebase_auth.signInWithCustomToken(x0,x1),
      pO: (x0,x1,x2) => new firebase_firestore.FieldPath(x0,x1,x2),
      pP: x0 => x0.type,
      q: (x0,x1,x2) => { x0[x1] = x2 },
      qB: Function.prototype.call.bind(DataView.prototype.getInt32),
      qC: (x0,x1) => x0.createTextNode(x1),
      qD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      qE: x0 => x0.scrollTop,
      qF: x0 => x0.now(),
      qG: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      qH: (a, i) => a.splice(i, 1),
      qI: x0 => x0.style,
      qJ: x0 => x0.name,
      qK: x0 => x0.imageBitmaps,
      qL: x0 => x0.authDomain,
      qM: x0 => x0.uid,
      qN: (x0,x1) => globalThis.firebase_auth.signInWithPopup(x0,x1),
      qO: (x0,x1,x2,x3) => new firebase_firestore.FieldPath(x0,x1,x2,x3),
      qP: x0 => x0.docChanges(),
      r: (o, p) => o[p],
      rB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      rC: (x0,x1) => { x0.id = x1 },
      rD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      rE: x0 => x0.offsetTop,
      rF: x0 => x0.performance,
      rG: (x0,x1) => { x0.value = x1 },
      rH: a => a.pop(),
      rI: (x0,x1) => { x0.src = x1 },
      rJ: x0 => x0.type,
      rK: x0 => x0.canvasKitMaximumSurfaces,
      rL: x0 => x0.projectId,
      rM: x0 => x0.enrollmentTime,
      rN: (x0,x1) => x0.setCustomParameters(x1),
      rO: (x0,x1,x2,x3,x4) => new firebase_firestore.FieldPath(x0,x1,x2,x3,x4),
      rP: x0 => x0.docs,
      s: () => globalThis,
      sB: o => o instanceof Uint16Array,
      sC: (x0,x1) => { x0.nonce = x1 },
      sD: x0 => x0.visibilityState,
      sE: x0 => x0.scrollLeft,
      sF: x0 => new Uint8Array(x0),
      sG: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      sH: (map, o, v) => map.set(o, v),
      sI: () => globalThis.document,
      sJ: x0 => x0.length,
      sK: x0 => x0.nextSibling,
      sL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      sM: x0 => x0.factorId,
      sN: (x0,x1) => x0.addScope(x1),
      sO: (x0,x1,x2,x3,x4,x5) => new firebase_firestore.FieldPath(x0,x1,x2,x3,x4,x5),
      sP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      t: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      tB: Function.prototype.call.bind(DataView.prototype.getUint16),
      tC: x0 => x0.nonce,
      tD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      tE: x0 => x0.offsetLeft,
      tF: (x0,x1,x2) => x0.slice(x1,x2),
      tG: (x0,x1) => { x0.value = x1 },
      tH: (map, o) => map.get(o),
      tI: x0 => x0.src,
      tJ: x0 => x0.files,
      tK: (x0,x1) => x0.debug(x1),
      tL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      tM: x0 => x0.displayName,
      tN: () => new firebase_auth.GoogleAuthProvider(),
      tO: (x0,x1,x2,x3,x4,x5,x6) => new firebase_firestore.FieldPath(x0,x1,x2,x3,x4,x5,x6),
      tP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      u: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      uB: o => o instanceof Int16Array,
      uC: () => globalThis.window.flutterConfiguration,
      uD: x0 => x0.disconnect(),
      uE: x0 => x0.offsetParent,
      uF: (x0,x1) => x0.decode(x1),
      uG: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      uH: () => new WeakMap(),
      uI: o => o.byteLength,
      uJ: (x0,x1) => { x0.display = x1 },
      uK: x0 => x0.hostElement,
      uL: (x0,x1,x2) => x0.onAuthStateChanged(x1,x2),
      uM: x0 => x0.hints,
      uN: (x0,x1,x2) => globalThis.firebase_auth.signInWithEmailAndPassword(x0,x1,x2),
      uO: (x0,x1,x2,x3,x4,x5,x6,x7) => new firebase_firestore.FieldPath(x0,x1,x2,x3,x4,x5,x6,x7),
      uP: x0 => globalThis.firebase_firestore.getDocs(x0),
      v: (x0,x1) => ({addView: x0,removeView: x1}),
      vB: Function.prototype.call.bind(DataView.prototype.getInt16),
      vC: (x0,x1) => x0.attachShadow(x1),
      vD: x0 => new Intl.Locale(x0),
      vE: (o, p, r) => o.replace(p, () => r),
      vF: (x0,x1) => x0.adoptText(x1),
      vG: x0 => x0.value,
      vH: x0 => x0.debugSkipFontRetryDelay,
      vI: () => new FileReader(),
      vJ: x0 => x0.style,
      vK: x0 => x0.location,
      vL: x0 => x0.call(),
      vM: x0 => x0.tenantId,
      vN: x0 => x0.signOut(),
      vO: (x0,x1,x2,x3,x4,x5,x6,x7,x8) => new firebase_firestore.FieldPath(x0,x1,x2,x3,x4,x5,x6,x7,x8),
      vP: x0 => globalThis.firebase_firestore.getDocsFromServer(x0),
      w: (l, r) => l === r,
      wB: o => o instanceof Uint8ClampedArray,
      wC: (x0,x1) => x0.createElement(x1),
      wD: x0 => x0.region,
      wE: (o, p, r) => o.replaceAll(p, () => r),
      wF: x0 => x0.first(),
      wG: x0 => x0.selectionDirection,
      wH: (x0,x1,x2) => x0.set(x1,x2),
      wI: (x0,x1) => x0.readAsArrayBuffer(x1),
      wJ: (x0,x1) => { x0.accept = x1 },
      wK: (x0,x1) => x0.getModifierState(x1),
      wL: x0 => x0.toJSON(),
      wM: x0 => x0.phoneNumber,
      wN: x0 => x0.tenantId,
      wO: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9) => new firebase_firestore.FieldPath(x0,x1,x2,x3,x4,x5,x6,x7,x8,x9),
      wP: x0 => globalThis.firebase_firestore.getDocsFromCache(x0),
      x: x0 => x0.random(),
      xB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      xC: x0 => x0.scale,
      xD: x0 => x0.script,
      xE: x0 => x0.deltaMode,
      xF: x0 => x0.next(),
      xG: x0 => x0.selectionStart,
      xH: x0 => x0.fontFallbackBaseUrl,
      xI: x0 => x0.result,
      xJ: (x0,x1) => { x0.multiple = x1 },
      xK: x0 => x0.metaKey,
      xL: x0 => x0.uid,
      xM: x0 => x0.email,
      xN: x0 => x0.currentUser,
      xO: () => globalThis.firebase_firestore.documentId(),
      xP: x0 => x0.path,
      y: () => globalThis.Math,
      yB: Function.prototype.call.bind(DataView.prototype.setInt32),
      yC: x0 => x0.visualViewport,
      yD: x0 => x0.language,
      yE: x0 => x0.deltaY,
      yF: x0 => x0.current(),
      yG: x0 => x0.selectionEnd,
      yH: (handle) => clearInterval(handle),
      yI: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      yJ: (x0,x1) => { x0.draggable = x1 },
      yK: x0 => x0.altKey,
      yL: (x0,x1) => globalThis.firebase_auth.connectAuthEmulator(x0,x1),
      yM: (x0,x1) => globalThis.firebase_auth.getMultiFactorResolver(x0,x1),
      yN: (x0,x1) => x0.querySelector(x1),
      yO: (x0,x1) => new firebase_firestore.GeoPoint(x0,x1),
      yP: x0 => globalThis.firebase_firestore.doc(x0),
      z: (x0,x1) => x0.prepend(x1),
      zB: Function.prototype.call.bind(DataView.prototype.setUint32),
      zC: x0 => x0.devicePixelRatio,
      zD: x0 => x0.languages,
      zE: x0 => x0.deltaX,
      zF: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      zG: x0 => x0.value,
      zH: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      zI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      zJ: (x0,x1) => { x0.type = x1 },
      zK: x0 => x0.ctrlKey,
      zL: x0 => x0.sessionStorage,
      zM: x0 => x0.customData,
      zN: (x0,x1) => { x0.id = x1 },
      zO: x0 => globalThis.firebase_firestore.vector(x0),
      zP: (x0,x1) => globalThis.firebase_firestore.collection(x0,x1),

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
