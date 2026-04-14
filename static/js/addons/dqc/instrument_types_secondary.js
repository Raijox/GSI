(function () {
    const ns = window.GSIAddonsDqc = window.GSIAddonsDqc || {};
    if (typeof ns.registerIntegratedSpec !== "function") return;
    if (typeof ns.createInstrumentTypeSpec !== "function") return;

    ns.registerIntegratedSpec("__instrument_types_secondary__", ns.createInstrumentTypeSpec({
        label: "Instrument Types Secondary Pass",
        passStage: "secondary",
    }));
})();
