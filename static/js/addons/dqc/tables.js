(function () {
    const ns = window.GSIAddonsDqc = window.GSIAddonsDqc || {};
    const tableOrder = [
        "header",
        "images",
        "legal",
        "names",
        "reference",
        "instrument_types",
        "additions",
        "record_series",
        "township_range",
    ];
    const tableLabels = {
        header: "Header",
        images: "Images",
        legal: "Legal",
        names: "Names",
        reference: "Reference",
        instrument_types: "Instrument Types",
        additions: "Additions",
        record_series: "Record Series",
        township_range: "Township/Range",
    };

    function normalizeTableKey(value) {
        const key = String(value || "").trim().toLowerCase();
        return Object.prototype.hasOwnProperty.call(tableLabels, key) ? key : "";
    }

    function createEmptyTableCounts() {
        const counts = {};
        tableOrder.forEach((key) => {
            counts[key] = 0;
        });
        return counts;
    }

    ns.tableOrder = tableOrder.slice();
    ns.tableLabels = { ...tableLabels };
    ns.normalizeTableKey = normalizeTableKey;
    ns.createEmptyTableCounts = createEmptyTableCounts;
})();
