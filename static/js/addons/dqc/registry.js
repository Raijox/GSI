(function () {
    const ns = window.GSIAddonsDqc = window.GSIAddonsDqc || {};
    const specs = ns.integratedSpecs || new Map();

    ns.integratedSpecs = specs;

    ns.registerIntegratedSpec = function registerIntegratedSpec(errorKey, spec) {
        const key = String(errorKey || "").trim();
        if (!key || !spec || typeof spec !== "object") return;
        specs.set(key, spec);
    };

    ns.getIntegratedSpec = function getIntegratedSpec(errorKey) {
        const key = String(errorKey || "").trim();
        return key ? (specs.get(key) || null) : null;
    };

    ns.getIntegratedLabel = function getIntegratedLabel(errorKey, fallbackLabel = "") {
        const spec = ns.getIntegratedSpec(errorKey);
        if (spec && spec.label) return String(spec.label);
        return String(fallbackLabel || errorKey || "");
    };
})();
