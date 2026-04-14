(function () {
    const ns = window.GSIAddonsDqc = window.GSIAddonsDqc || {};
    if (typeof ns.registerIntegratedSpec !== "function") return;

    ns.createAdditionsSpec = function createAdditionsSpec(options = {}) {
        const passStage = String(options.passStage || "primary").trim().toLowerCase() === "secondary"
            ? "secondary"
            : "primary";
        const isSecondary = passStage === "secondary";
        const label = String(options.label || (isSecondary ? "Additions Secondary Pass" : "Additions")).trim();

        return {
            type: "correcting_additions",
            label,
            routeBase: "additions-corrections",
            passStage,
            idField: "id",
            statusMap: { pending: "pending", fixed: "mapped", all: "" },
            toFixed(row) {
                return String(row && row.new_addition_name || "").trim() !== ""
                    || Number(row && row.is_fixed || 0) === 1;
            },
            summary(row) {
                const original = String(row && row.original_addition_value || "").trim();
                const mapped = String(row && row.new_addition_name || "").trim();
                const block = String(row && row.block_value || "").trim();
                const lot = String(row && row.lot_value || "").trim();
                if (!isSecondary) {
                    return `original=${original}; mapped=${mapped || "(none)"}; block=${block}; lot=${lot}`;
                }
                const primary = String(row && row.primary_pass_addition_value || "").trim();
                return `original=${original}; primary=${primary || "(none)"}; secondary=${mapped || "(keep primary)"}; block=${block}; lot=${lot}`;
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
                    promptAdditionNeedsAddedName,
                } = ctx;
                if (!integratedEditor) return;

                const hasPreviousAdditionMatch = Number(row && row.has_previous_match || source && source.has_previous_match || 0) === 1;
                const primaryValue = String(source.primary_pass_addition_value || "").trim();

                integratedEditor.innerHTML = `
                    <div class="col-12"><div class="small text-muted">Original addition: <strong class="${hasPreviousAdditionMatch ? "addons-overlay-match-name" : ""}">${esc(String(source.original_addition_value || ""))}</strong></div></div>
                    ${isSecondary ? `<div class="col-12"><div class="small text-muted">Primary pass value: <strong>${esc(primaryValue || "(none)")}</strong></div></div>` : ""}
                    <div class="col-12">
                        <label class="form-label small mb-1" for="dqcIntSearch">Search Keli Additions</label>
                        <div class="addons-itc-search-wrap">
                            <div class="d-flex justify-content-between align-items-center">
                                <div class="small text-muted">Search by name or description</div>
                                <button id="dqcIntSearchHideBtn" class="btn btn-outline-secondary btn-sm py-0 px-2" type="button" hidden>Hide</button>
                            </div>
                            <input id="dqcIntSearch" class="form-control" type="text" placeholder="Search by name or description...">
                            <div id="dqcIntSearchResults" class="addons-itc-search-results mt-1" hidden></div>
                        </div>
                    </div>
                    <div class="col-12">
                        <div id="dqcIntSelectedTypeMeta" class="addons-itc-selected-meta mb-2 small text-muted">${isSecondary ? "No secondary addition selected." : "No new addition selected."}</div>
                    </div>
                    <div class="col-12 d-flex gap-2">
                        <button id="dqcIntMatchAllPrevBtn" class="btn btn-outline-info btn-sm" type="button">Match All with Previous Selection</button>
                        <button id="dqcIntNeedsAddBtn" class="btn btn-outline-warning btn-sm" type="button">Mark As Needs Added</button>
                    </div>
                `;

                const selectedMeta = document.getElementById("dqcIntSelectedTypeMeta");
                const renderSelectedMeta = (picked) => {
                    if (!selectedMeta) return;
                    const safeName = String((picked || {}).name || "").trim();
                    if (!safeName) {
                        selectedMeta.textContent = isSecondary
                            ? "No secondary addition selected."
                            : "No new addition selected.";
                        return;
                    }
                    const activeTag = Number((picked || {}).is_active || 0) === 1
                        ? `<span class="badge text-bg-success">Active</span>`
                        : `<span class="badge text-bg-secondary">Inactive</span>`;
                    const needsAddedTag = Number((picked || {}).needs_added || 0) === 1
                        ? `<span class="badge text-bg-warning">Needs Added</span>`
                        : "";
                    const desc = String((picked || {}).description || "").trim();
                    selectedMeta.innerHTML = `
                        <div class="d-flex flex-wrap gap-1 align-items-center">
                            <strong>${esc(safeName)}</strong>
                            ${activeTag}
                            ${needsAddedTag}
                        </div>
                        ${desc ? `<div class="mt-1">${esc(desc)}</div>` : ""}
                    `;
                };

                renderSelectedMeta({
                    name: source.new_addition_name,
                    is_active: source.new_is_active,
                    description: source.new_addition_description,
                    needs_added: source.needs_added,
                });

                wireIntegratedLookup(row, {
                    inputId: "dqcIntSearch",
                    resultsId: "dqcIntSearchResults",
                    hideId: "dqcIntSearchHideBtn",
                    searchRoute: "additions-corrections/search-keli-additions",
                    action: isSecondary ? "dqc_integrated_search_additions_secondary" : "dqc_integrated_search_additions",
                    onPick: (picked) => {
                        renderSelectedMeta(picked);
                        submitIntegratedAction(
                            "assign",
                            {
                                name: String(picked.name || "").trim(),
                                type_id: String(picked.type_id || "").trim(),
                                description: String(picked.description || "").trim(),
                                is_active: String(Number(picked.is_active || 0) ? 1 : 0),
                                apply_all_matching_original: false,
                            },
                            isSecondary ? "dqc_integrated_additions_assign_secondary" : "dqc_integrated_additions_assign",
                        ).catch((err) => setBanner(err.message, "danger"));
                    },
                    formatter: (result, idx) => `
                        <button type="button" class="addons-itc-search-row" data-dqc-int-idx="${idx}">
                            <div class="d-flex flex-wrap gap-1 align-items-center">
                                <strong>${esc(String(result.name || ""))}</strong>
                                <span class="badge ${Number(result.is_active || 0) === 1 ? "text-bg-success" : "text-bg-secondary"}">${Number(result.is_active || 0) === 1 ? "Active" : "Inactive"}</span>
                                ${Number(result.needs_added || 0) === 1 ? `<span class="badge text-bg-warning">Needs Added</span>` : ""}
                            </div>
                            ${String(result.description || "").trim() ? `<div class="small text-muted mt-1">${esc(String(result.description || "").trim())}</div>` : ""}
                        </button>
                    `,
                });

                const needsAddBtn = document.getElementById("dqcIntNeedsAddBtn");
                if (needsAddBtn) {
                    needsAddBtn.addEventListener("click", async () => {
                        const customName = await promptAdditionNeedsAddedName(
                            String(source.new_addition_name || source.primary_pass_addition_value || source.original_addition_value || "").trim(),
                        );
                        if (customName === null || !customName) return;
                        submitIntegratedAction(
                            "mark-needs-added",
                            { custom_name: customName },
                            isSecondary ? "dqc_integrated_additions_needs_added_secondary" : "dqc_integrated_additions_needs_added",
                        ).catch((err) => setBanner(err.message, "danger"));
                    });
                }

                const matchAllBtn = document.getElementById("dqcIntMatchAllPrevBtn");
                if (matchAllBtn) {
                    matchAllBtn.addEventListener("click", () => {
                        submitIntegratedAction(
                            "match-all-previous",
                            {},
                            isSecondary ? "dqc_integrated_additions_match_all_previous_secondary" : "dqc_integrated_additions_match_all_previous",
                        ).catch((err) => setBanner(err.message, "danger"));
                    });
                }
            },
        };
    };

    ns.registerIntegratedSpec("__additions__", ns.createAdditionsSpec());
})();
