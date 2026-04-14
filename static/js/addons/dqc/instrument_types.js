(function () {
    const ns = window.GSIAddonsDqc = window.GSIAddonsDqc || {};
    if (typeof ns.registerIntegratedSpec !== "function") return;

    ns.createInstrumentTypeSpec = function createInstrumentTypeSpec(options = {}) {
        const passStage = String(options.passStage || "primary").trim().toLowerCase() === "secondary"
            ? "secondary"
            : "primary";
        const isSecondary = passStage === "secondary";
        const label = String(options.label || (isSecondary ? "Instrument Types Secondary Pass" : "Instrument Types")).trim();

        return {
            type: "correcting_instrument_types",
            label,
            routeBase: "instrument-type-corrections",
            passStage,
            idField: "id",
            statusMap: { pending: "pending", fixed: "mapped", all: "" },
            toFixed(row) {
                return String(row && row.new_instrument_type_name || "").trim() !== ""
                    || Number(row && row.is_fixed || 0) === 1;
            },
            summary(row) {
                const original = String(row && row.original_instrument_type || "").trim();
                const mapped = String(row && row.new_instrument_type_name || "").trim();
                if (!isSecondary) {
                    return `original=${original}; mapped=${mapped || "(none)"}`;
                }
                const primary = String(row && row.primary_pass_instrument_type_value || "").trim();
                return `original=${original}; primary=${primary || "(none)"}; secondary=${mapped || "(keep primary)"}`;
            },
            supportsStatus: true,
            supportsDelete: true,
            supportsInstrumentDelete: true,
            renderEditor(ctx) {
                const {
                    row,
                    source,
                    integratedEditor,
                    esc,
                    wireIntegratedLookup,
                    submitIntegratedAction,
                    setBanner,
                } = ctx;
                if (!integratedEditor) return;

                const primaryValue = String(source.primary_pass_instrument_type_value || "").trim();
                integratedEditor.innerHTML = `
                    <div class="col-12"><div class="small text-muted">Original instrument type: <strong>${esc(String(source.original_instrument_type || ""))}</strong></div></div>
                    ${isSecondary ? `<div class="col-12"><div class="small text-muted">Primary pass value: <strong>${esc(primaryValue || "(none)")}</strong></div></div>` : ""}
                    <div class="col-12">
                        <label class="form-label small mb-1" for="dqcIntSearch">Search Keli Instrument Types</label>
                        <div class="addons-itc-search-wrap">
                            <div class="d-flex justify-content-between align-items-center">
                                <div id="dqcIntSearchHelp" class="small text-muted">Searching name field only</div>
                                <button id="dqcIntSearchHideBtn" class="btn btn-outline-secondary btn-sm py-0 px-2" type="button" hidden>Hide</button>
                            </div>
                            <div class="btn-group w-100 mb-2" role="group" aria-label="Integrated instrument type search field">
                                <button type="button" class="btn btn-outline-secondary active" data-dqc-int-search-field="name">Name</button>
                                <button type="button" class="btn btn-outline-secondary" data-dqc-int-search-field="description">Description</button>
                            </div>
                            <input id="dqcIntSearch" class="form-control" type="text" placeholder="Search by name...">
                            <div id="dqcIntSearchResults" class="addons-itc-search-results mt-1" hidden></div>
                        </div>
                    </div>
                    <div class="col-12">
                        <div id="dqcIntSelectedTypeMeta" class="addons-itc-selected-meta mb-2 small text-muted">${isSecondary ? "No secondary instrument type selected." : "No new instrument type selected."}</div>
                    </div>
                    <div class="col-12 d-flex gap-2">
                        <button id="dqcIntMatchAllPrevBtn" class="btn btn-outline-info btn-sm" type="button">Match All with Previous Selection</button>
                    </div>
                `;

                const selectedMeta = document.getElementById("dqcIntSelectedTypeMeta");
                const renderSelectedMeta = (picked) => {
                    if (!selectedMeta) return;
                    const safeName = String((picked || {}).name || "").trim();
                    if (!safeName) {
                        selectedMeta.textContent = isSecondary
                            ? "No secondary instrument type selected."
                            : "No new instrument type selected.";
                        return;
                    }
                    const activeTag = Number((picked || {}).is_active || 0) === 1
                        ? `<span class="badge text-bg-success">Active</span>`
                        : `<span class="badge text-bg-secondary">Inactive</span>`;
                    const recordType = String((picked || {}).record_type || "").trim() || "Unknown Record Type";
                    const desc = String((picked || {}).description || "").trim();
                    selectedMeta.innerHTML = `
                        <div class="d-flex flex-wrap gap-1 align-items-center">
                            <strong>${esc(safeName)}</strong>
                            ${activeTag}
                            ${recordType ? `<span class="badge text-bg-info">${esc(recordType)}</span>` : ""}
                        </div>
                        ${desc ? `<div class="mt-1">${esc(desc)}</div>` : ""}
                    `;
                };

                renderSelectedMeta({
                    name: source.new_instrument_type_name,
                    record_type: source.new_record_type,
                    is_active: source.new_is_active,
                    description: source.new_instrument_type_description,
                });

                let integratedSearchField = "name";
                const integratedSearchInput = document.getElementById("dqcIntSearch");
                const integratedSearchHelp = document.getElementById("dqcIntSearchHelp");
                const integratedSearchFieldButtons = Array.from(document.querySelectorAll("[data-dqc-int-search-field]"));
                const updateIntegratedSearchUi = () => {
                    integratedSearchFieldButtons.forEach((btn) => {
                        const isActive = String(btn.getAttribute("data-dqc-int-search-field") || "") === integratedSearchField;
                        btn.classList.toggle("active", isActive);
                        btn.setAttribute("aria-pressed", isActive ? "true" : "false");
                    });
                    if (integratedSearchHelp) {
                        integratedSearchHelp.textContent = integratedSearchField === "description"
                            ? "Searching description field only"
                            : "Searching name field only";
                    }
                    if (integratedSearchInput) {
                        integratedSearchInput.placeholder = integratedSearchField === "description"
                            ? "Search by description..."
                            : "Search by name...";
                    }
                };

                const lookupController = wireIntegratedLookup(row, {
                    inputId: "dqcIntSearch",
                    resultsId: "dqcIntSearchResults",
                    hideId: "dqcIntSearchHideBtn",
                    searchRoute: "instrument-type-corrections/search-keli-types",
                    action: isSecondary ? "dqc_integrated_search_instrument_types_secondary" : "dqc_integrated_search_instrument_types",
                    extendQuery: () => ({ search_field: integratedSearchField }),
                    onPick: (picked) => {
                        renderSelectedMeta(picked);
                        submitIntegratedAction(
                            "assign",
                            {
                                name: String(picked.name || "").trim(),
                                type_id: String(picked.type_id || "").trim(),
                                record_type: String(picked.record_type || "").trim(),
                                is_active: String(Number(picked.is_active || 0) ? 1 : 0),
                                apply_all_matching_original: false,
                            },
                            isSecondary ? "dqc_integrated_instrument_secondary_assign" : "dqc_integrated_instrument_assign",
                        ).catch((err) => setBanner(err.message, "danger"));
                    },
                    formatter: (result, idx) => `
                        <button type="button" class="addons-itc-search-row" data-dqc-int-idx="${idx}">
                            <div class="d-flex flex-wrap gap-1 align-items-center">
                                <strong>${esc(String(result.name || ""))}</strong>
                                <span class="badge ${Number(result.is_active || 0) === 1 ? "text-bg-success" : "text-bg-secondary"}">${Number(result.is_active || 0) === 1 ? "Active" : "Inactive"}</span>
                                ${String(result.record_type || "").trim() ? `<span class="badge text-bg-info">${esc(String(result.record_type || "").trim())}</span>` : ""}
                            </div>
                            ${String(result.description || "").trim() ? `<div class="small text-muted mt-1">${esc(String(result.description || "").trim())}</div>` : ""}
                        </button>
                    `,
                });

                integratedSearchFieldButtons.forEach((btn) => {
                    btn.addEventListener("click", () => {
                        const nextField = String(btn.getAttribute("data-dqc-int-search-field") || "").trim().toLowerCase();
                        if (!nextField || nextField === integratedSearchField) return;
                        integratedSearchField = nextField;
                        updateIntegratedSearchUi();
                        if (lookupController && typeof lookupController.reload === "function") {
                            lookupController.reload(String((integratedSearchInput || {}).value || "")).catch((err) => setBanner(err.message, "danger"));
                        }
                    });
                });

                const matchAllBtn = document.getElementById("dqcIntMatchAllPrevBtn");
                if (matchAllBtn) {
                    matchAllBtn.addEventListener("click", () => {
                        submitIntegratedAction(
                            "match-all-previous",
                            {},
                            isSecondary ? "dqc_integrated_instrument_match_all_previous_secondary" : "dqc_integrated_instrument_match_all_previous",
                        ).catch((err) => setBanner(err.message, "danger"));
                    });
                }

                updateIntegratedSearchUi();
            },
        };
    };

    ns.registerIntegratedSpec("__instrument_types__", ns.createInstrumentTypeSpec());
})();
