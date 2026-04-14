(function () {
    const ns = window.GSIAddonsDqc = window.GSIAddonsDqc || {};
    if (typeof ns.registerIntegratedSpec !== "function") return;
    if (typeof ns.createAdditionsSpec !== "function") return;

    ns.registerIntegratedSpec("__additions_secondary__", ns.createAdditionsSpec({
        label: "Additions Secondary Pass",
        passStage: "secondary",
    }));
})();
