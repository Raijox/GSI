(function () {
    const ns = window.GSIAddonsDqc = window.GSIAddonsDqc || {};

    ns.renderApp = function renderDataQualityCorrectionsApp(app, env = {}) {
        const {
            api,
            esc,
            setBanner,
            popupAlert,
            showAuditLogDetails,
            popupConfirm,
            promptAdditionNeedsAddedName,
            popupProgressStart,
            popupProgressStop,
            withProcessingPopup,
            reportDebug,
            state,
            renderAppsList,
            getWorkspaceTeardown,
            setWorkspaceTeardown,
        } = env;
        let workspaceTeardown = typeof getWorkspaceTeardown === "function"
            ? getWorkspaceTeardown()
            : null;
        const root = document.getElementById("addonAppWorkspace");
        if (!root) return;
        if (typeof workspaceTeardown === "function") {
            workspaceTeardown();
            workspaceTeardown = null;
            if (typeof setWorkspaceTeardown === "function") setWorkspaceTeardown(null);
        }
        const workspace = root.closest(".addons-workspace");
        if (workspace) {
            workspace.classList.add("addons-workspace-lock-scroll");
            workspace.classList.add("addons-workspace-dqc-static");
        }
        root.classList.remove("addons-empty-state");
        root.classList.add("addons-mii-workspace");
        const scope = app.working_county_scope || null;
        const scopeError = app.working_county_scope_error || "";
        const canRun = Boolean(scope);
        const tableOrder = Array.isArray(ns.tableOrder) && ns.tableOrder.length
            ? ns.tableOrder.slice()
            : ["header", "images", "legal", "names", "reference", "instrument_types", "additions", "record_series", "township_range"];
        const tableLabelMap = ns.tableLabels && typeof ns.tableLabels === "object"
            ? { ...ns.tableLabels }
            : {
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
        const normalizeTableKey = typeof ns.normalizeTableKey === "function"
            ? ns.normalizeTableKey
            : (value) => {
                const key = String(value || "").trim().toLowerCase();
                return Object.prototype.hasOwnProperty.call(tableLabelMap, key) ? key : "";
            };
        const createEmptyTableCounts = typeof ns.createEmptyTableCounts === "function"
            ? ns.createEmptyTableCounts
            : () => tableOrder.reduce((acc, key) => {
                acc[key] = 0;
                return acc;
            }, {});
        const fixedTableKey = normalizeTableKey(app.dqc_table);
        const hasFixedTable = !!fixedTableKey;
        const tableControlMarkup = `
            <div id="dqcTableSelectorWrap" class="col-md-4${hasFixedTable ? " d-none" : ""}">
                <label class="form-label" for="dqcTableSelector"><i class="bi bi-table me-1"></i>Split Table</label>
                <select id="dqcTableSelector" class="form-select" ${canRun ? "" : "disabled"}>
                    ${tableOrder.map((key) => `<option value="${esc(key)}">${esc(tableLabelMap[key] || key)}</option>`).join("")}
                </select>
            </div>
        `;
        const queueControlMarkup = `
            <div class="col-md-2">
                <label class="form-label" for="dqcStatusFilter"><i class="bi bi-check2-square me-1"></i>Queue</label>
                <select id="dqcStatusFilter" class="form-select" ${canRun ? "" : "disabled"}>
                    <option value="pending">Pending</option>
                    <option value="fixed">Reviewed</option>
                    <option value="all">All</option>
                </select>
                ${scopeError ? `<div class="form-text text-danger mt-1">${esc(scopeError)}</div>` : ""}
            </div>
        `;
        const errorControlMarkup = `
            <div class="col-md-3">
                <label class="form-label" for="dqcErrorFilter"><i class="bi bi-funnel-fill me-1"></i>Error Type</label>
                <select id="dqcErrorFilter" class="form-select" ${canRun ? "" : "disabled"}>
                    <option value="">No errors detected</option>
                </select>
            </div>
        `;
        const passControlMarkup = `
            <div id="dqcPassWrap" class="col-md-3" hidden>
                <label class="form-label" for="dqcPassFilter"><i class="bi bi-layers me-1"></i>Pass</label>
                <select id="dqcPassFilter" class="form-select" ${canRun ? "" : "disabled"}>
                    <option value="primary">Primary</option>
                    <option value="secondary">Secondary</option>
                </select>
            </div>
        `;
        const controlsMarkup = hasFixedTable
            ? `${errorControlMarkup}${queueControlMarkup}${passControlMarkup}${tableControlMarkup}`
            : `${tableControlMarkup}${queueControlMarkup}${errorControlMarkup}${passControlMarkup}`;

        root.innerHTML = `
            <div class="addons-mii-shell addons-dqc-shell">
                <div id="dqcHeaderBar" class="addons-meta-card mb-2">
                    <div id="dqcControlsRow" class="row g-3">
                        ${controlsMarkup}
                    </div>
                </div>

                <div class="row g-2 addons-mii-main-row addons-dqc-main-row">
                    <div id="dqcQueueCol" class="col-lg-5 d-flex">
                        <section id="dqcQueuePane" class="addons-meta-card addons-mii-pane addons-overlay-host w-100">
                            <div id="dqcEditOverlay" class="addons-dqc-edit-overlay addons-tool-edit-overlay" hidden>
                                <div class="addons-dqc-edit-overlay-header d-flex align-items-center justify-content-between">
                                    <h6 class="mb-0">Edit Record</h6>
                                    <button id="dqcEditCloseBtn" class="btn btn-outline-secondary btn-sm" type="button">Close</button>
                                </div>
                                <div class="addons-dqc-edit-overlay-body">
                                    <div class="row g-2 mb-2" id="dqcHeaderFields">
                                        <div id="dqcDynamicFieldsHost" class="row g-2"></div>
                                        <div class="col-12 d-flex align-items-end gap-2">
                                            <button id="dqcApplyFieldsBtn" class="btn btn-outline-warning btn-sm" type="button" disabled>Apply Field Changes</button>
                                            <button id="dqcMarkAllSameBtn" class="btn btn-outline-info btn-sm" type="button" disabled hidden>Mark All As Same</button>
                                            <button id="dqcNeedsInsertBtn" class="btn btn-outline-danger btn-sm" type="button" disabled>Flag Needs Inserted</button>
                                        </div>
                                    </div>
                                    <div id="dqcIntegratedEditor" class="row g-2 mb-2" hidden></div>
                                </div>
                            </div>
                            <h6 class="mb-2">Issues Queue</h6>
                            <div id="dqcPreviewMeta" class="small text-muted mb-2">Select an issue from the queue. Ctrl/Cmd+click to multi-select, Shift+click for range.</div>
                            <div id="dqcSnapshot" class="addons-itc-selected-meta mb-2 small text-muted d-none">No issue selected.</div>
                            <div id="dqcQueueBody" class="addons-mii-pane-body addons-mii-queue-body">
                                <div id="dqcItemsList" class="addons-mii-list small text-muted">Run scan to load issues.</div>
                            </div>
                        </section>
                    </div>
                    <div id="dqcImageMainCol" class="col-lg-7 d-flex">
                        <div id="dqcPreviewWrap" class="addons-mii-preview-wrap w-100"></div>
                    </div>
                </div>

                <div id="dqcActionBar" class="addons-meta-card addons-dqc-actionbar mt-2">
                    <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
                        <button id="dqcPrevPageBtn" class="btn btn-outline-secondary btn-sm" type="button" ${canRun ? "" : "disabled"}>Prev</button>
                        <div id="dqcPageMeta" class="small text-muted text-center flex-fill text-truncate">Page 1 / 1 · 0 total</div>
                        <button id="dqcNextPageBtn" class="btn btn-outline-secondary btn-sm" type="button" ${canRun ? "" : "disabled"}>Next</button>
                    </div>
                    <div class="d-flex flex-wrap gap-3 align-items-center">
                        <div class="d-flex align-items-center gap-2">
                            <button id="dqcScanGroupToggle" class="btn btn-outline-primary btn-sm" type="button">
                                <i class="bi bi-search me-1"></i>Scan Actions
                            </button>
                            <div id="dqcScanGroupPanel" class="d-none flex-wrap gap-2 align-items-center">
                                <button id="dqcScanBtn" class="btn btn-primary btn-sm" type="button" ${canRun ? "" : "disabled"}>
                                    <i class="bi bi-search me-1"></i>Scan
                                </button>
                                <button id="dqcViewLogsBtn" class="btn btn-outline-secondary btn-sm" type="button" ${canRun ? "" : "disabled"}>
                                    <i class="bi bi-list-ul me-1"></i>View Logs
                                </button>
                            </div>
                        </div>
                        <div class="d-flex align-items-center gap-2">
                            <button id="dqcReviewGroupToggle" class="btn btn-outline-primary btn-sm" type="button">
                                <i class="bi bi-check2-square me-1"></i>Review Actions
                            </button>
                            <div id="dqcReviewGroupPanel" class="d-none flex-wrap gap-2 align-items-center">
                                <button id="dqcEditRecordBtn" class="btn btn-outline-success btn-sm" type="button" disabled>Edit Record</button>
                                <button id="dqcMarkFixedBtn" class="btn btn-warning btn-sm" type="button" disabled>Mark Fixed</button>
                                <button id="dqcMarkDeleteBtn" class="btn btn-outline-danger btn-sm" type="button" disabled>Mark Record for Delete</button>
                                <button id="dqcRestoreDeleteBtn" class="btn btn-outline-success btn-sm" type="button" disabled>Restore Record</button>
                                <button id="dqcIgnoreBtn" class="btn btn-outline-info btn-sm" type="button" disabled>Ignore</button>
                                <button id="dqcMarkPendingBtn" class="btn btn-outline-secondary btn-sm" type="button" disabled>Mark Pending</button>
                                <button id="dqcUndoLastBtn" class="btn btn-outline-warning btn-sm" type="button" ${canRun ? "" : "disabled"}>Undo Last Change</button>
                                <button id="dqcMarkInstrumentDeleteBtn" class="btn btn-danger btn-sm" type="button" disabled>Mark Instrument for Delete</button>
                                <button id="dqcRestoreInstrumentBtn" class="btn btn-outline-danger btn-sm" type="button" disabled>Restore Instrument</button>
                            </div>
                        </div>
                    </div>
                </div>

                <div id="dqcLogsWrap" class="addons-logs-wrap mt-2" hidden>
                    <div class="d-flex justify-content-between align-items-center mb-2">
                        <div class="small text-muted">Showing only your logs for active working county scope.</div>
                        <button id="dqcLogsHideBtn" class="btn btn-outline-secondary btn-sm" type="button">Hide</button>
                    </div>
                    <div id="dqcLogsTableHost"></div>
                </div>
            </div>
        `;

        const tableSelector = document.getElementById("dqcTableSelector");
        const statusFilter = document.getElementById("dqcStatusFilter");
        const errorFilter = document.getElementById("dqcErrorFilter");
        const passWrap = document.getElementById("dqcPassWrap");
        const passFilter = document.getElementById("dqcPassFilter");
        const scanBtn = document.getElementById("dqcScanBtn");
        const viewLogsBtn = document.getElementById("dqcViewLogsBtn");
        const scanGroupToggle = document.getElementById("dqcScanGroupToggle");
        const reviewGroupToggle = document.getElementById("dqcReviewGroupToggle");
        const scanGroupPanel = document.getElementById("dqcScanGroupPanel");
        const reviewGroupPanel = document.getElementById("dqcReviewGroupPanel");
        const actionBar = document.getElementById("dqcActionBar");
        const logsWrap = document.getElementById("dqcLogsWrap");
        const logsHideBtn = document.getElementById("dqcLogsHideBtn");
        const logsHost = document.getElementById("dqcLogsTableHost");
        const itemsList = document.getElementById("dqcItemsList");
        const prevPageBtn = document.getElementById("dqcPrevPageBtn");
        const nextPageBtn = document.getElementById("dqcNextPageBtn");
        const pageMeta = document.getElementById("dqcPageMeta");
        const editRecordBtn = document.getElementById("dqcEditRecordBtn");
        const editOverlay = document.getElementById("dqcEditOverlay");
        const editCloseBtn = document.getElementById("dqcEditCloseBtn");
        const previewMeta = document.getElementById("dqcPreviewMeta");
        const snapshotEl = document.getElementById("dqcSnapshot");
        const previewWrap = document.getElementById("dqcPreviewWrap");
        const markFixedBtn = document.getElementById("dqcMarkFixedBtn");
        const markDeleteBtn = document.getElementById("dqcMarkDeleteBtn");
        const markInstrumentDeleteBtn = document.getElementById("dqcMarkInstrumentDeleteBtn");
        const restoreInstrumentBtn = document.getElementById("dqcRestoreInstrumentBtn");
        const restoreDeleteBtn = document.getElementById("dqcRestoreDeleteBtn");
        const ignoreBtn = document.getElementById("dqcIgnoreBtn");
        const markPendingBtn = document.getElementById("dqcMarkPendingBtn");
        const undoLastBtn = document.getElementById("dqcUndoLastBtn");
        const headerFieldsWrap = document.getElementById("dqcHeaderFields");
        const dynamicFieldsHost = document.getElementById("dqcDynamicFieldsHost");
        const integratedEditor = document.getElementById("dqcIntegratedEditor");
        const applyFieldsBtn = document.getElementById("dqcApplyFieldsBtn");
        const markAllSameBtn = document.getElementById("dqcMarkAllSameBtn");
        const needsInsertBtn = document.getElementById("dqcNeedsInsertBtn");
        const queuePane = document.getElementById("dqcQueuePane");
        const queueCol = document.getElementById("dqcQueueCol");
        const queueBody = document.getElementById("dqcQueueBody");
        const imageMainCol = document.getElementById("dqcImageMainCol");
        const mainRow = root.querySelector(".addons-mii-main-row");
        if (!tableSelector || !statusFilter || !errorFilter || !passWrap || !passFilter || !scanBtn || !viewLogsBtn || !scanGroupToggle || !reviewGroupToggle || !scanGroupPanel || !reviewGroupPanel || !actionBar || !logsWrap || !logsHideBtn || !logsHost || !itemsList || !prevPageBtn || !nextPageBtn || !pageMeta || !editRecordBtn || !editOverlay || !editCloseBtn || !previewMeta || !snapshotEl || !previewWrap || !markFixedBtn || !markDeleteBtn || !markInstrumentDeleteBtn || !restoreInstrumentBtn || !restoreDeleteBtn || !ignoreBtn || !markPendingBtn || !undoLastBtn || !headerFieldsWrap || !dynamicFieldsHost || !integratedEditor || !applyFieldsBtn || !markAllSameBtn || !needsInsertBtn || !queuePane || !queueCol || !queueBody || !imageMainCol || !mainRow) return;

        let activeTable = fixedTableKey || "header";
        let instrumentTypePassStage = "primary";
        let additionsPassStage = "primary";
        let issues = [];
        let selectedId = null;
        let selectedIndex = -1;
        let selectionAnchorIndex = -1;
        let selectedIds = new Set();
        let currentErrorRows = [];
        let logs = [];
        let activeFieldInputs = [];
        let townshipRangeReferenceDataPromise = null;
        let hasScanned = false;
        let currentPage = 1;
        const pageSize = 100;
        let totalPages = 1;
        let totalCount = 0;
        let tablePendingCounts = createEmptyTableCounts();
        function isIntegratedInstrumentTypeType(type) {
            const normalized = String(type || "").trim();
            return normalized === "correcting_instrument_types";
        }
        function isIntegratedAdditionsType(type) {
            const normalized = String(type || "").trim();
            return normalized === "correcting_additions";
        }
        function activeIntegratedPassStage(tableKey = activeTable) {
            const table = String(tableKey || "").trim();
            if (table === "instrument_types") return instrumentTypePassStage;
            if (table === "additions") return additionsPassStage;
            return "primary";
        }
        function activeSecondaryIntegratedErrorKey(tableKey = activeTable) {
            const table = String(tableKey || "").trim();
            const passStage = activeIntegratedPassStage(table);
            if (passStage !== "secondary") return "";
            if (table === "instrument_types") return "__instrument_types_secondary__";
            if (table === "additions") return "__additions_secondary__";
            return "";
        }
        function integratedErrorKeysForTable(tableKey = activeTable) {
            const table = String(tableKey || "").trim();
            const keys = [];
            if (table === "legal") keys.push("__legal_other__");
            if (table === "names") keys.push("__missing_names__");
            const secondaryKey = activeSecondaryIntegratedErrorKey(table);
            if (secondaryKey) keys.push(secondaryKey);
            return keys;
        }
        function syncPassControls() {
            const table = String(activeTable || "").trim();
            const show = table === "instrument_types" || table === "additions";
            passWrap.hidden = !show;
            passFilter.disabled = !canRun || !show;
            if (!show) return;
            passFilter.value = activeIntegratedPassStage(table);
        }
        const inlineViewer = window.GSICore && typeof window.GSICore.attachImageViewer === "function"
            ? window.GSICore.attachImageViewer(previewWrap, { initialMessage: "No image selected." })
            : null;
        const editableFieldDefs = {
            col02varchar: { label: "col02varchar", width: "col-md-4" },
            col03varchar: { label: "col03varchar", width: "col-md-4" },
            col04varchar: { label: "col04varchar", width: "col-md-4" },
            col05varchar: { label: "col05varchar", width: "col-md-4" },
            col06varchar: { label: "col06varchar", width: "col-md-4" },
            col07varchar: { label: "col07varchar", width: "col-md-4" },
            col08varchar: { label: "col08varchar", width: "col-md-4" },
            key_id: { label: "key_id", width: "col-md-4" },
            book: { label: "book", width: "col-md-4" },
            page_number: { label: "page_number", width: "col-md-4" },
            beginning_page: { label: "beginning_page", width: "col-md-4" },
            ending_page: { label: "ending_page", width: "col-md-4" },
            col20other: { label: "col20other", width: "col-md-4" },
            year: { label: "year", width: "col-md-4" },
            record_series_internal_id: { label: "record_series_internal_id", width: "col-md-4" },
        };
        const editableFieldsByError = {
            headerDuplicateInstrumentNumber: ["col02varchar"],
            headerMissingInstrumentNumber: ["col02varchar"],
            headerInstrumentNumberSixDigits: ["col02varchar"],
            headerNonNumericInstrumentNumber: ["col02varchar"],
            headerMissingRecordSeries: ["col06varchar"],
            headerIncorrectRecordSeries: ["col06varchar"],
            headerMissingBeginningPageNumber: ["beginning_page"],
            headerMissingEndingPageNumber: ["ending_page"],
            headerNonNumericPageNumber: ["beginning_page"],
            headerBeginningPageFourDigits: ["beginning_page"],
            headerEndingPageFourDigits: ["ending_page"],
            headerMissingBookNumber: ["book"],
            headerValidBookRange: ["book"],
            headerBookSixDigits: ["book"],
            headerDuplicateBookPageNumber: ["book", "beginning_page"],
            imageDuplicateBookPageNumber: ["book", "page_number"],
            imageIncorrectBookLength: ["book"],
            imageIncorrectPageLength: ["page_number"],
            imageNonNumericPageNumber: ["page_number"],
            imageNonNumericBookNumber: ["book"],
            imageMissingBookNumber: ["book"],
            imageMissingPageNumber: ["page_number"],
            imageValidBookRange: ["book"],
            imageBookSixDigits: ["book"],
            imagePageFourDigits: ["page_number"],
            legalOutOfCountyTownshipRanges: ["col03varchar", "col04varchar"],
            legalOutOfRangeSection: ["col02varchar"],
            legalOutOfRangeQuarterSections: ["col08varchar"],
            instTypeMissingLookup: ["col03varchar"],
            additionMissingLookup: ["col05varchar"],
            recordSeriesMissingYear: ["year"],
            recordSeriesMissingLookup: ["year"],
            recordSeriesIncorrectInternalId: ["record_series_internal_id"],
            townshipRangeMissingValues: ["col03varchar", "col04varchar"],
            townshipRangeOutOfCounty: ["col03varchar", "col04varchar"],
            nameDuplicateNames: ["col02varchar", "col03varchar"],
            refRecordedNotWithinBookRange: ["col02varchar", "col20other"],
            refBookSixDigits: ["col02varchar"],
            refPageFourDigits: ["col03varchar"],
            refMissingBookNumber: ["col02varchar"],
            refMissingPageNumber: ["col03varchar"],
            refNonNumericBookNumber: ["col02varchar"],
            refNonNumericPageNumber: ["col03varchar"],
        };

        function severityBadgeClass(value) {
            const v = String(value || "").toLowerCase();
            if (v === "warn" || v === "warning") return "warn";
            if (v === "error" || v === "critical") return "error";
            return "info";
        }
        function selectedItem() {
            if (Number.isInteger(selectedIndex) && selectedIndex >= 0 && selectedIndex < issues.length) {
                return issues[selectedIndex] || null;
            }
            return issues.find((x) => String(x.id) === String(selectedId)) || null;
        }
        function selectedItems() {
            if (!selectedIds || !selectedIds.size) {
                const single = selectedItem();
                return single ? [single] : [];
            }
            return issues.filter((x) => selectedIds.has(String(x.id)));
        }
        function renderTableSelectorOptions() {
            const selectorKeys = hasFixedTable ? [fixedTableKey] : tableOrder;
            tableSelector.innerHTML = selectorKeys.map((key) => {
                const label = tableLabelMap[key] || key;
                const count = Number(tablePendingCounts[key] || 0) || 0;
                return `<option value="${esc(key)}">${esc(`${label} (${count})`)}</option>`;
            }).join("");
            tableSelector.value = activeTable;
        }
        function setTablePendingCountsFromObject(counts) {
            const source = counts && typeof counts === "object" ? counts : {};
            tablePendingCounts = createEmptyTableCounts();
            tableOrder.forEach((key) => {
                tablePendingCounts[key] = Number(source[key] || 0) || 0;
            });
            renderTableSelectorOptions();
        }
        function setTableState() {
            if (hasFixedTable) activeTable = fixedTableKey;
            renderTableSelectorOptions();
            syncPassControls();
        }
        function renderPager() {
            const usableTotalPages = Math.max(1, totalPages);
            pageMeta.textContent = `Page ${currentPage} / ${usableTotalPages} · ${totalCount} total`;
            prevPageBtn.disabled = !canRun || usableTotalPages <= 1;
            nextPageBtn.disabled = !canRun || usableTotalPages <= 1;
        }
        function setAwaitingScanState() {
            issues = [];
            currentErrorRows = [];
            selectedId = null;
            selectedIndex = -1;
            selectionAnchorIndex = -1;
            selectedIds = new Set();
            totalCount = 0;
            totalPages = 1;
            currentPage = 1;
            tablePendingCounts = createEmptyTableCounts();
            renderTableSelectorOptions();
            syncPassControls();
            errorFilter.innerHTML = `<option value="">Run scan to detect errors</option>`;
            errorFilter.value = "";
            errorFilter.disabled = true;
            itemsList.innerHTML = `<div class="small text-muted">Run scan to load issues.</div>`;
            setSelection(null);
            renderPager();
        }
        async function loadIntegratedErrorCounts(statusOverride = "", tableOverride = "", options = {}) {
            const tableKey = String(tableOverride || activeTable || "").trim();
            const errorKeys = integratedErrorKeysForTable(tableKey);
            if (!errorKeys.length) return [];
            const rows = await Promise.all(errorKeys.map(async (errorKey) => {
                const spec = integratedSpecForError(errorKey);
                if (!spec) return null;
                const mappedStatus = mapIntegratedStatus(spec, statusOverride || statusFilter.value || "pending");
                const q = new URLSearchParams();
                if (mappedStatus) q.set("status", mappedStatus);
                q.set("page", "1");
                q.set("page_size", "1");
                if (String(spec.passStage || "").trim()) q.set("pass_stage", String(spec.passStage).trim());
                const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/${spec.routeBase}/items?${q.toString()}`, "GET", null, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_integrated_counts",
                });
                const issueCount = Number(payload.total_count || payload.count || 0) || 0;
                if (!issueCount) return null;
                return {
                    error_key: errorKey,
                    error_label: displayErrorLabel(errorKey, String(spec.label || "")),
                    issue_count: issueCount,
                };
            }));
            return rows.filter((row) => row && (Number(row.issue_count || 0) || 0) > 0);
        }
        async function refreshTableSelectorCounts() {
            if (!hasScanned) {
                renderTableSelectorOptions();
                return;
            }
            const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/counts`, "GET", null, {
                addon_id: app.id,
                addon_type: app.type,
                addon_action: "dqc_counts",
            });
            hasScanned = Boolean(payload && payload.has_scanned) || hasScanned;
            if (payload && payload.counts && typeof payload.counts === "object") {
                setTablePendingCountsFromObject(payload.counts);
            } else {
                renderTableSelectorOptions();
            }
        }
        function integratedErrorTarget(errorKey) {
            const map = {
                "__instrument_types__": "correcting_instrument_types",
                "__additions__": "correcting_additions",
                "__legal_other__": "fix_legal_type_others",
                "__missing_names__": "missing_grantor_grantee_names",
                "__missed_indexing_images__": "missed_indexing_images",
                "__indexed_image_missing_file__": "indexed_images_missing_files",
                "__working_images_not_in_source__": "working_images_not_in_source",
            };
            return map[String(errorKey || "").trim()] || "";
        }
        function displayErrorLabel(errorKey, fallbackLabel = "") {
            const key = String(errorKey || "").trim();
            const registrySpec = window.GSIAddonsDqc && typeof window.GSIAddonsDqc.getIntegratedSpec === "function"
                ? window.GSIAddonsDqc.getIntegratedSpec(key)
                : null;
            const registryLabel = registrySpec && registrySpec.label ? String(registrySpec.label) : "";
            if (registryLabel) return registryLabel;
            const mapped = {
                "__instrument_types__": "Instrument Types",
                "__additions__": "Additions",
                "__legal_other__": "Legal Type Others",
                "__missing_names__": "Missing Names",
                "__missed_indexing_images__": "Missed Indexed Images",
                "__indexed_image_missing_file__": "Indexed Images Missing File",
                "__working_images_not_in_source__": "Working Images Not In Source",
                instTypeMissingLookup: "Instrument Types",
                additionMissingLookup: "Additions",
                recordSeriesMissingYear: "Record Series",
                recordSeriesMissingLookup: "Record Series",
                recordSeriesIncorrectInternalId: "Record Series",
                townshipRangeMissingValues: "Township / Range Missing",
                townshipRangeOutOfCounty: "Township / Range Out Of County",
            };
            return mapped[key] || String(fallbackLabel || key);
        }
        function integratedSpecForError(errorKey) {
            const registrySpec = window.GSIAddonsDqc && typeof window.GSIAddonsDqc.getIntegratedSpec === "function"
                ? window.GSIAddonsDqc.getIntegratedSpec(errorKey)
                : null;
            if (registrySpec) return registrySpec;
            const target = integratedErrorTarget(errorKey);
            if (target === "fix_legal_type_others") {
                return {
                    type: target,
                    routeBase: "fix-legal-type-others",
                    idField: "legal_row_id",
                    statusMap: { pending: "pending", fixed: "fixed", all: "" },
                    toFixed: (row) => Number(row.is_fixed || 0) === 1,
                    summary: (row) => `legal_type=${String(row.legal_type || "").trim()}; free_form=${String(row.free_form_legal || "").trim() || "(blank)"}`,
                    supportsStatus: true,
                    supportsDelete: true,
                    supportsInstrumentDelete: true,
                };
            }
            if (target === "missing_grantor_grantee_names") {
                return {
                    type: target,
                    routeBase: "missing-grantor-grantee-names",
                    idField: "name_row_id",
                    statusMap: { pending: "pending", fixed: "fixed", all: "" },
                    toFixed: (row) => Number(row.is_fixed || 0) === 1,
                    summary: (row) => `party_type=${String(row.col02varchar || "").trim()}; name=${String(row.col03varchar || "").trim() || "(blank)"}; counterpart=${String(row.counterpart_name || "").trim() || "(none)"}`,
                    supportsStatus: true,
                    supportsDelete: true,
                    supportsInstrumentDelete: true,
                };
            }
            if (target === "missed_indexing_images") {
                return {
                    type: target,
                    routeBase: "missed-indexing-images",
                    idField: "id",
                    statusMap: { pending: "pending", fixed: "needs_indexed", all: "" },
                    toFixed: (row) => String(row.review_status || "").trim().toLowerCase() === "needs_indexed",
                    summary: (row) => String(row.relative_path || row.file_name || "").trim(),
                    hasImages: true,
                    supportsStatus: true,
                    supportsDelete: false,
                    supportsInstrumentDelete: false,
                };
            }
            if (target === "indexed_images_missing_files") {
                return {
                    type: target,
                    routeBase: "data-quality-corrections/indexed-images-missing-files",
                    idField: "id",
                    statusMap: { pending: "pending", fixed: "confirmed_missing", all: "" },
                    toFixed: (row) => String(row.review_status || "").trim().toLowerCase() === "confirmed_missing",
                    summary: (row) => `book=${String(row.book_value || "").trim()}; page=${String(row.page_value || "").trim()}; path=${String(row.relative_path || "").trim()}`,
                    hasImages: false,
                    supportsStatus: true,
                    supportsDelete: false,
                    supportsInstrumentDelete: false,
                };
            }
            if (target === "working_images_not_in_source") {
                return {
                    type: target,
                    routeBase: "data-quality-corrections/working-images-not-in-source",
                    idField: "id",
                    statusMap: { pending: "pending", fixed: "confirmed_missing", all: "" },
                    toFixed: (row) => String(row.review_status || "").trim().toLowerCase() === "confirmed_missing",
                    summary: (row) => String(row.relative_path || row.file_name || "").trim(),
                    hasImages: true,
                    supportsStatus: true,
                    supportsDelete: false,
                    supportsInstrumentDelete: false,
                };
            }
            return null;
        }
        function mapDqcStatusToBase(statusKeyRaw) {
            const statusKey = String(statusKeyRaw || "pending").trim().toLowerCase();
            return statusKey;
        }
        function mapIntegratedStatus(spec, statusKeyRaw) {
            const statusKey = String(statusKeyRaw || "pending").trim().toLowerCase();
            if (!spec || !spec.type) return "pending";
            const normalized = mapDqcStatusToBase(statusKey);
            return Object.prototype.hasOwnProperty.call(spec.statusMap || {}, normalized)
                ? spec.statusMap[normalized]
                : "pending";
        }
        async function loadIntegratedIssues(errorKey) {
            const spec = integratedSpecForError(errorKey);
            if (!spec) {
                issues = [];
                renderItems();
                return;
            }
            const mappedStatus = mapIntegratedStatus(spec, statusFilter.value || "pending");
            const q = new URLSearchParams();
            if (mappedStatus) q.set("status", mappedStatus);
            q.set("page", String(currentPage));
            q.set("page_size", String(pageSize));
            if (String(spec.passStage || "").trim()) q.set("pass_stage", String(spec.passStage).trim());
            const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/${spec.routeBase}/items?${q.toString()}`, "GET", null, {
                addon_id: app.id,
                addon_type: app.type,
                addon_action: "dqc_integrated_items",
            });
            totalCount = Number(payload.total_count || 0) || 0;
            totalPages = Number(payload.total_pages || Math.max(1, Math.ceil(totalCount / pageSize))) || 1;
            if (totalPages < 1) totalPages = 1;
            if (currentPage > totalPages) {
                currentPage = totalPages;
                renderPager();
                return loadIntegratedIssues(errorKey);
            }
            const rows = Array.isArray(payload.items) ? payload.items : [];
            issues = rows.map((row, idx) => {
                const rowId = row[spec.idField];
                const idVal = String(rowId ?? `${idx + 1}`);
                const hasPreviousMatch = Number(
                    row.has_previous_match
                    ?? row.has_prior_mapping
                    ?? 0
                ) === 1 ? 1 : 0;
                return {
                    id: `integrated:${String(errorKey || spec.type)}:${idVal}`,
                    source_row_id: idVal,
                    error_key: String(errorKey || ""),
                    error_label: displayErrorLabel(errorKey),
                    file_key: String(row.file_key || row.header_file_key || row.fn || ""),
                    col01varchar: String(
                        row.col01varchar
                        || row.relative_path
                        || row.keyOriginalValue
                        || row.original_instrument_type
                        || row.original_addition_value
                        || row.col03varchar
                        || ""
                    ),
                    snapshot: spec.summary(row),
                    is_fixed: spec.toFixed(row) ? 1 : 0,
                    has_previous_match: hasPreviousMatch,
                    __integrated: {
                        spec,
                        addon_id: app.id,
                        addon_type: app.type,
                        row_id: idVal,
                        row,
                    },
                };
            });
            renderPager();
            renderItems();
        }
        function resetIntegratedEditor() {
            integratedEditor.hidden = true;
            integratedEditor.innerHTML = "";
        }
        function getTownshipRangeReferenceData() {
            if (!townshipRangeReferenceDataPromise) {
                townshipRangeReferenceDataPromise = api(`/api/addons/apps/${encodeURIComponent(app.id)}/fix-legal-type-others/reference-data`, "GET", null, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_township_range_reference_data",
                }).then((payload) => {
                    const townshipRangeMap = payload && typeof payload.township_range_map === "object"
                        ? payload.township_range_map
                        : {};
                    return {
                        sections: Array.isArray(payload.sections) ? payload.sections.map((x) => String(x || "").trim()).filter(Boolean) : [],
                        townshipOptions: Array.isArray(payload.township_options) ? payload.township_options.map((x) => String(x || "").trim()).filter(Boolean) : [],
                        rangeOptions: Array.isArray(payload.range_options) ? payload.range_options.map((x) => String(x || "").trim()).filter(Boolean) : [],
                        townshipRangeMap,
                    };
                }).catch((err) => {
                    townshipRangeReferenceDataPromise = null;
                    throw err;
                });
            }
            return townshipRangeReferenceDataPromise;
        }
        function buildRangeTownshipMap(townshipRangeMap) {
            const map = {};
            Object.keys(townshipRangeMap || {}).forEach((township) => {
                const ranges = Array.isArray(townshipRangeMap[township]) ? townshipRangeMap[township] : [];
                ranges.forEach((rng) => {
                    if (!map[rng]) map[rng] = [];
                    if (!map[rng].includes(township)) map[rng].push(township);
                });
            });
            return map;
        }
        function dedupeOptionValues(values) {
            const seen = new Set();
            return (Array.isArray(values) ? values : []).map((value) => String(value || "").trim()).filter((value) => {
                if (!value || seen.has(value)) return false;
                seen.add(value);
                return true;
            });
        }
        function renderSelectOptions(selectEl, values, selectedValue) {
            if (!selectEl) return;
            const normalizedSelected = String(selectedValue || "").trim();
            const items = dedupeOptionValues(values);
            const optionValues = normalizedSelected && !items.includes(normalizedSelected)
                ? [normalizedSelected, ...items]
                : items;
            selectEl.innerHTML = [`<option value=""></option>`, ...optionValues.map((value) => `<option value="${esc(value)}">${esc(value)}</option>`)].join("");
            selectEl.value = normalizedSelected && optionValues.includes(normalizedSelected) ? normalizedSelected : "";
        }
        function syncTownshipRangeOptionPairs(options) {
            const townshipSelect = options && options.townshipSelect;
            const rangeSelect = options && options.rangeSelect;
            if (!townshipSelect || !rangeSelect) return;
            const townshipRangeMap = options && options.townshipRangeMap && typeof options.townshipRangeMap === "object"
                ? options.townshipRangeMap
                : {};
            const rangeTownshipMap = options && options.rangeTownshipMap && typeof options.rangeTownshipMap === "object"
                ? options.rangeTownshipMap
                : {};
            const allTownshipOptions = dedupeOptionValues(options && options.allTownshipOptions);
            const allRangeOptions = dedupeOptionValues(options && options.allRangeOptions);
            const townshipValue = String(options && options.townshipValue || "").trim();
            const rangeValue = String(options && options.rangeValue || "").trim();
            const changedField = String(options && options.changedField || "").trim().toLowerCase();
            const rangesForTownship = townshipValue && Array.isArray(townshipRangeMap[townshipValue])
                ? dedupeOptionValues(townshipRangeMap[townshipValue])
                : [];
            const townshipsForRange = rangeValue && Array.isArray(rangeTownshipMap[rangeValue])
                ? dedupeOptionValues(rangeTownshipMap[rangeValue])
                : [];
            const validPair = townshipValue && rangeValue
                ? (Array.isArray(townshipRangeMap[townshipValue]) && townshipRangeMap[townshipValue].includes(rangeValue))
                : true;
            let allowedTownships = allTownshipOptions.slice();
            let allowedRanges = allRangeOptions.slice();
            let nextTownship = townshipValue;
            let nextRange = rangeValue;
            if (townshipValue && !rangeValue) {
                allowedRanges = rangesForTownship;
            } else if (!townshipValue && rangeValue) {
                allowedTownships = townshipsForRange;
            } else if (townshipValue && rangeValue && validPair) {
                allowedTownships = townshipsForRange.length ? townshipsForRange : allTownshipOptions.slice();
                allowedRanges = rangesForTownship.length ? rangesForTownship : allRangeOptions.slice();
            } else if (townshipValue && rangeValue) {
                if (changedField === "range") {
                    allowedTownships = townshipsForRange;
                    nextTownship = townshipsForRange.includes(townshipValue) ? townshipValue : "";
                } else {
                    allowedRanges = rangesForTownship;
                    nextRange = rangesForTownship.includes(rangeValue) ? rangeValue : "";
                }
            }
            renderSelectOptions(townshipSelect, allowedTownships, nextTownship);
            renderSelectOptions(rangeSelect, allowedRanges, nextRange);
        }
        function renderIntegratedLookupResults(rows, host, formatter) {
            if (!host) return;
            const list = Array.isArray(rows) ? rows : [];
            if (!list.length) {
                host.innerHTML = `<div class="small text-muted">No matches found.</div>`;
                host.hidden = false;
                return;
            }
            host.innerHTML = list.map((row, idx) => formatter(row, idx)).join("");
            host.hidden = false;
        }
        function wireIntegratedLookup(row, options) {
            if (!row || !row.__integrated || !options) return;
            const addonId = row.__integrated.addon_id;
            const addonType = row.__integrated.addon_type;
            const spec = row.__integrated.spec || {};
            const searchInput = document.getElementById(options.inputId);
            const searchResults = document.getElementById(options.resultsId);
            const searchHideBtn = document.getElementById(options.hideId);
            const mappedInput = document.getElementById("dqcIntMappedName");
            if (!searchInput || !searchResults || !searchHideBtn) return;
            let searchRows = [];
            let searchTimer = null;
            const hideResults = () => {
                searchResults.hidden = true;
                searchHideBtn.hidden = true;
            };
            const showResults = () => {
                searchResults.hidden = false;
                searchHideBtn.hidden = false;
            };
            const loadRows = async (query) => {
                const q = new URLSearchParams();
                if (query) q.set("q", query);
                q.set("limit", "2000");
                if (String(spec.passStage || "").trim()) q.set("pass_stage", String(spec.passStage).trim());
                if (typeof options.extendQuery === "function") {
                    const extraQuery = options.extendQuery() || {};
                    Object.entries(extraQuery).forEach(([key, value]) => {
                        const safeKey = String(key || "").trim();
                        const safeValue = String(value ?? "").trim();
                        if (!safeKey || safeValue === "") return;
                        q.set(safeKey, safeValue);
                    });
                }
                const payload = await api(`/api/addons/apps/${encodeURIComponent(addonId)}/${options.searchRoute}?${q.toString()}`, "GET", null, {
                    addon_id: addonId,
                    addon_type: addonType,
                    addon_action: options.action,
                });
                searchRows = Array.isArray(payload.items) ? payload.items : [];
                renderIntegratedLookupResults(searchRows, searchResults, options.formatter);
                showResults();
            };
            searchInput.addEventListener("input", () => {
                const val = String(searchInput.value || "").trim();
                if (searchTimer) window.clearTimeout(searchTimer);
                searchTimer = window.setTimeout(() => {
                    loadRows(val).catch((err) => setBanner(err.message, "danger"));
                }, 180);
            });
            searchInput.addEventListener("focus", () => {
                loadRows(String(searchInput.value || "").trim()).catch((err) => setBanner(err.message, "danger"));
            });
            searchHideBtn.addEventListener("click", hideResults);
            searchResults.addEventListener("click", (event) => {
                const btn = event.target.closest("[data-dqc-int-idx]");
                if (!btn) return;
                const idx = Number(btn.getAttribute("data-dqc-int-idx"));
                if (!Number.isFinite(idx) || idx < 0 || idx >= searchRows.length) return;
                const picked = searchRows[idx] || {};
                if (mappedInput) mappedInput.value = String(picked.name || "").trim();
                const typeIdInput = document.getElementById("dqcIntMappedTypeId");
                const recTypeInput = document.getElementById("dqcIntMappedRecordType");
                const activeInput = document.getElementById("dqcIntMappedIsActive");
                const descInput = document.getElementById("dqcIntMappedDescription");
                if (typeIdInput) typeIdInput.value = String(picked.type_id || "").trim();
                if (recTypeInput) recTypeInput.value = String(picked.record_type || "").trim();
                if (activeInput) activeInput.value = String(Number(picked.is_active || 0) ? 1 : 0);
                if (descInput) descInput.value = String(picked.description || "").trim();
                if (typeof options.onPick === "function") {
                    options.onPick(picked);
                }
                hideResults();
            });
            hideResults();
            return {
                reload: (query = "") => loadRows(String(query || "").trim()),
                hide: hideResults,
            };
        }
        function hideEditOverlay() {
            editOverlay.hidden = true;
        }
        async function callIntegratedActionForRow(row, pathSuffix, body, actionLabel, rowIdOverride = "") {
            if (!row || !row.__integrated) return null;
            const addonId = row.__integrated.addon_id;
            const addonType = row.__integrated.addon_type;
            const spec = row.__integrated.spec || {};
            const targetRowId = String(rowIdOverride || row.__integrated.row_id || "").trim();
            const payloadBody = body && typeof body === "object" ? { ...body } : {};
            if (String(spec.passStage || "").trim()) {
                payloadBody.pass_stage = String(spec.passStage).trim();
            }
            return api(`/api/addons/apps/${encodeURIComponent(addonId)}/${spec.routeBase}/items/${encodeURIComponent(targetRowId)}/${pathSuffix}`, "POST", payloadBody, {
                addon_id: addonId,
                addon_type: addonType,
                addon_action: actionLabel,
            });
        }
        async function submitIntegratedAction(pathSuffix, body, actionLabel, rowIdOverride = "") {
            const row = selectedItem();
            if (!row || !row.__integrated) return;
            const normalizedPathSuffix = String(pathSuffix || "").trim().toLowerCase();
            const runAction = async () => {
                const payload = await callIntegratedActionForRow(row, pathSuffix, body, actionLabel, rowIdOverride);
                setBanner(payload.message || "Update complete.", "success");
                await loadErrorTypes();
                await loadIssues();
                await refreshPendingBadgeForActiveTable();
                queueResizeLayout();
            };
            if (normalizedPathSuffix === "mark-same" || normalizedPathSuffix === "match-all-previous") {
                await withProcessingPopup(
                    "Applying Mark As Same",
                    "Processing matching records. Please wait until this finishes.",
                    runAction
                );
                return;
            }
            await runAction();
        }
        async function submitLegalTypeOtherStyleActionForTownshipRange(pathSuffix, body, actionLabel, rowIdOverride = "") {
            const row = selectedItem();
            if (!row) return;
            let targetRowId = String(rowIdOverride || row.integrated_row_id || "").trim();
            if (!targetRowId) {
                const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/township-range-legal-context`, "GET", null, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_township_range_legal_context",
                });
                const legalRows = Array.isArray(payload.items) ? payload.items : [];
                const initialRowId = String(payload.initial_legal_row_id || "").trim();
                const targetTownship = String(row.col03varchar || "").trim();
                const targetRange = String(row.col04varchar || "").trim();
                const match = legalRows.find((entry) => String(entry.legal_row_id || "").trim() === initialRowId)
                    || legalRows.find((entry) => (
                        String(entry.col03varchar || "").trim() === targetTownship
                        && String(entry.col04varchar || "").trim() === targetRange
                    ))
                    || legalRows[0]
                    || null;
                targetRowId = String((match || {}).legal_row_id || "").trim();
            }
            if (!targetRowId) throw new Error("No related legal row is available for this township/range record.");
            const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/fix-legal-type-others/items/${encodeURIComponent(targetRowId)}/${pathSuffix}`, "POST", body && typeof body === "object" ? { ...body } : {}, {
                addon_id: app.id,
                addon_type: app.type,
                addon_action: actionLabel,
            });
            await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/set-fixed?table=township_range`, "POST", {
                is_fixed: true,
                note: "applied_fields",
            }, {
                addon_id: app.id,
                addon_type: app.type,
                addon_action: "dqc_township_range_set_fixed_after_legal_apply",
            });
            setBanner(payload.message || "Update complete.", "success");
            await loadErrorTypes();
            await loadIssues();
            await refreshPendingBadgeForActiveTable();
            queueResizeLayout();
        }
        function renderLegalTypeOtherEditorMarkup(source) {
            const quarterTokens = String((source && source.col08varchar) || "")
                .split(/[,\s]+/)
                .map((x) => String(x || "").trim().toUpperCase())
                .filter(Boolean);
            return `
                <div class="col-12">
                    <ul class="nav nav-tabs nav-sm mb-2">
                        <li class="nav-item"><button id="dqcIntTabAdditions" class="nav-link active py-1 px-2" type="button">Additions</button></li>
                        <li class="nav-item"><button id="dqcIntTabSTR" class="nav-link py-1 px-2" type="button">STR</button></li>
                        <li class="nav-item"><button id="dqcIntTabQuarter" class="nav-link py-1 px-2" type="button">Quarter Section</button></li>
                        <li class="nav-item"><button id="dqcIntTabFreeForm" class="nav-link py-1 px-2" type="button">Free Form Legal</button></li>
                        <li class="nav-item"><button id="dqcIntTabSelectLegal" class="nav-link py-1 px-2" type="button">Select Legal</button></li>
                    </ul>
                </div>
                <div id="dqcIntPaneAdditions" class="col-12">
                    <div class="row g-2">
                        <div class="col-md-12">
                            <div class="addons-itc-search-wrap">
                                <div class="d-flex justify-content-between align-items-center">
                                    <label class="form-label small mb-1" for="dqcIntAddition">Addition</label>
                                    <button id="dqcIntAdditionHideBtn" class="btn btn-outline-secondary btn-sm py-0 px-2" type="button" hidden>Hide</button>
                                </div>
                                <div class="input-group input-group-sm">
                                    <input id="dqcIntAddition" class="form-control form-control-sm" type="text" placeholder="Search additions..." value="${esc(String((source && source.col05varchar) || ""))}">
                                    <button id="dqcIntAdditionBrowseBtn" class="btn btn-outline-secondary" type="button" title="Show addition list">
                                        <i class="bi bi-chevron-down"></i>
                                    </button>
                                </div>
                                <div id="dqcIntAdditionResults" class="addons-itc-search-results mt-1" hidden></div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <label class="form-label small mb-1" for="dqcIntLot">Lot</label>
                            <input id="dqcIntLot" class="form-control form-control-sm" type="text" value="${esc(String((source && source.col07varchar) || ""))}">
                        </div>
                        <div class="col-md-3">
                            <label class="form-label small mb-1" for="dqcIntBlock">Block</label>
                            <input id="dqcIntBlock" class="form-control form-control-sm" type="text" value="${esc(String((source && source.col06varchar) || ""))}">
                        </div>
                    </div>
                </div>
                <div id="dqcIntPaneSTR" class="col-12" hidden>
                    <div class="row g-2">
                        <div class="col-md-4">
                            <label class="form-label small mb-1" for="dqcIntSection">Section</label>
                            <select id="dqcIntSection" class="form-select form-select-sm"></select>
                        </div>
                        <div class="col-md-4">
                            <label class="form-label small mb-1" for="dqcIntTownship">Township</label>
                            <select id="dqcIntTownship" class="form-select form-select-sm"></select>
                        </div>
                        <div class="col-md-4">
                            <label class="form-label small mb-1" for="dqcIntRange">Range</label>
                            <select id="dqcIntRange" class="form-select form-select-sm"></select>
                        </div>
                    </div>
                </div>
                <div id="dqcIntPaneQuarter" class="col-12" hidden>
                    <div class="row g-2">
                        <div class="col-md-8">
                            <label class="form-label small mb-1" for="dqcIntQuarterSelect">Quarter Section</label>
                            <select id="dqcIntQuarterSelect" class="form-select form-select-sm">
                                <option value=""></option>
                                ${["NE","SE","NW","SW","N","S","E","W","N2","S2","E2","W2"].map((q) => `<option value="${q}">${q}</option>`).join("")}
                            </select>
                        </div>
                        <div class="col-md-4 d-flex align-items-end">
                            <button id="dqcIntQuarterAddBtn" class="btn btn-outline-primary btn-sm w-100" type="button">Add Quarter</button>
                        </div>
                        <div class="col-12">
                            <div id="dqcIntQuarterChips" class="d-flex flex-wrap gap-1">
                                ${quarterTokens.map((q, idx) => `
                                    <span class="badge text-bg-info d-inline-flex align-items-center gap-1">
                                        ${esc(q)}
                                        <button type="button" class="btn btn-sm btn-link text-white p-0 border-0" data-dqc-int-quarter-rm="${idx}">x</button>
                                    </span>
                                `).join("")}
                            </div>
                        </div>
                    </div>
                </div>
                <div id="dqcIntPaneFreeForm" class="col-12" hidden>
                    <div class="row g-2">
                        <div class="col-12">
                            <label class="form-label small mb-1">Free Form Legal</label>
                            <div class="d-flex flex-column gap-1">
                                <label class="d-flex align-items-center gap-2 small"><input type="radio" name="dqcIntFreeFormLegal" value="No Legal Description">No Legal Description</label>
                                <label class="d-flex align-items-center gap-2 small"><input type="radio" name="dqcIntFreeFormLegal" value="Incomplete Legal Description">Incomplete Legal Description</label>
                                <label class="d-flex align-items-center gap-2 small"><input type="radio" name="dqcIntFreeFormLegal" value="Not in County">Not in County</label>
                                <label class="d-flex align-items-center gap-2 small"><input type="radio" name="dqcIntFreeFormLegal" value="">Empty</label>
                            </div>
                        </div>
                    </div>
                </div>
                <div id="dqcIntPaneSelectLegal" class="col-12" hidden>
                    <div class="small text-muted mb-1">Choose which legal row to edit for this record key.</div>
                    <div id="dqcIntSelectedLegalMeta" class="small mb-1">Selected Legal: #${esc(String((source && source.legal_row_id) || ""))}</div>
                    <div id="dqcIntLegalList" class="addons-mii-list" style="max-height: 220px; overflow: auto;"></div>
                </div>
                <div class="col-12 d-flex gap-2">
                    <button id="dqcIntApplyBtn" class="btn btn-warning btn-sm" type="button">Apply</button>
                    <button id="dqcIntAddLegalBtn" class="btn btn-outline-warning btn-sm" type="button">Add Additional Legal</button>
                </div>
            `;
        }
        function bindLegalTypeOtherEditorHandlers(options) {
            const source = options && options.source ? options.source : {};
            const addonId = String((options && options.addonId) || app.id || "").trim();
            const addonType = String((options && options.addonType) || app.type || "").trim();
            const initialLegalRowId = String((options && options.initialLegalRowId) || source.legal_row_id || "").trim();
            const headerFileKey = String((options && options.headerFileKey) || source.header_file_key || source.file_key || "").trim();
            const keyValue = String((options && options.col01varchar) || source.col01varchar || "").trim();
            const contextRoute = String((options && options.contextRoute) || "").trim();
            const submitAction = typeof (options && options.submitAction) === "function" ? options.submitAction : null;
            const pickInitialLegalRow = typeof (options && options.pickInitialLegalRow) === "function" ? options.pickInitialLegalRow : null;
            const searchAdditionsAction = String((options && options.searchAdditionsAction) || "dqc_integrated_search_legal_other_additions").trim();
            const relatedLegalsAction = String((options && options.relatedLegalsAction) || "dqc_integrated_legal_other_related_legals").trim();
            const applyAction = String((options && options.applyAction) || "dqc_integrated_legal_other_apply").trim();
            const addAdditionalAction = String((options && options.addAdditionalAction) || "dqc_integrated_legal_other_additional").trim();
            const applyBtn = document.getElementById("dqcIntApplyBtn");
            const tabAdditions = document.getElementById("dqcIntTabAdditions");
            const tabSTR = document.getElementById("dqcIntTabSTR");
            const tabQuarter = document.getElementById("dqcIntTabQuarter");
            const tabFreeForm = document.getElementById("dqcIntTabFreeForm");
            const tabSelectLegal = document.getElementById("dqcIntTabSelectLegal");
            const paneAdditions = document.getElementById("dqcIntPaneAdditions");
            const paneSTR = document.getElementById("dqcIntPaneSTR");
            const paneQuarter = document.getElementById("dqcIntPaneQuarter");
            const paneFreeForm = document.getElementById("dqcIntPaneFreeForm");
            const paneSelectLegal = document.getElementById("dqcIntPaneSelectLegal");
            const legalList = document.getElementById("dqcIntLegalList");
            const selectedLegalMeta = document.getElementById("dqcIntSelectedLegalMeta");
            const quarterSelect = document.getElementById("dqcIntQuarterSelect");
            const quarterAddBtn = document.getElementById("dqcIntQuarterAddBtn");
            const quarterChips = document.getElementById("dqcIntQuarterChips");
            const addLegalBtn = document.getElementById("dqcIntAddLegalBtn");
            const sectionSelect = document.getElementById("dqcIntSection");
            const townshipSelect = document.getElementById("dqcIntTownship");
            const rangeSelect = document.getElementById("dqcIntRange");
            const additionInput = document.getElementById("dqcIntAddition");
            const additionBrowseBtn = document.getElementById("dqcIntAdditionBrowseBtn");
            const additionResults = document.getElementById("dqcIntAdditionResults");
            const additionHideBtn = document.getElementById("dqcIntAdditionHideBtn");
            if (!applyBtn) return;
            let selectedLegalRowId = initialLegalRowId;
            let quarters = String(source.col08varchar || "")
                .split(/[,\s]+/)
                .map((x) => String(x || "").trim().toUpperCase())
                .filter(Boolean);
            let legalRows = [];
            let additions = [];
            let addSearchTimer = null;
            let townshipRangeMap = {};
            let rangeTownshipMap = {};
            let allRangeOptions = [];
            let allTownshipOptions = [];
            const hideAdditionResults = () => {
                if (additionResults) additionResults.hidden = true;
                if (additionHideBtn) additionHideBtn.hidden = true;
            };
            const showAdditionResults = () => {
                if (additionResults) additionResults.hidden = false;
                if (additionHideBtn) additionHideBtn.hidden = false;
            };
            const renderAdditionResults = () => {
                if (!additionResults) return;
                if (!additions.length) {
                    showAdditionResults();
                    additionResults.innerHTML = `<div class="small text-muted">No matches found.</div>`;
                    return;
                }
                showAdditionResults();
                additionResults.innerHTML = additions.map((entry, idx) => {
                    const activeTag = Number(entry.is_active || 0) === 1
                        ? `<span class="badge text-bg-success">Active</span>`
                        : `<span class="badge text-bg-secondary">Inactive</span>`;
                    const desc = String(entry.description || "").trim();
                    return `
                        <button type="button" class="addons-itc-search-row" data-dqc-int-addition-idx="${idx}">
                            <div class="d-flex flex-wrap gap-1 align-items-center">
                                <strong>${esc(entry.name || "")}</strong>
                                ${activeTag}
                            </div>
                            ${desc ? `<div class="small text-muted mt-1">${esc(desc)}</div>` : ""}
                        </button>
                    `;
                }).join("");
            };
            const loadAdditions = async (query) => {
                const q = new URLSearchParams();
                if (query) q.set("q", query);
                q.set("limit", "2000");
                const payload = await api(`/api/addons/apps/${encodeURIComponent(addonId)}/fix-legal-type-others/search-keli-additions?${q.toString()}`, "GET", null, {
                    addon_id: addonId,
                    addon_type: addonType,
                    addon_action: searchAdditionsAction,
                });
                additions = Array.isArray(payload.items) ? payload.items : [];
                renderAdditionResults();
            };
            const syncTownshipRangeOptions = (townshipValue, rangeValue, changedField = "") => {
                syncTownshipRangeOptionPairs({
                    townshipSelect,
                    rangeSelect,
                    townshipRangeMap,
                    rangeTownshipMap,
                    allTownshipOptions,
                    allRangeOptions,
                    townshipValue,
                    rangeValue,
                    changedField,
                });
            };
            const loadReferenceData = async () => {
                const payload = await getTownshipRangeReferenceData();
                townshipRangeMap = payload && typeof payload.townshipRangeMap === "object"
                    ? payload.townshipRangeMap
                    : {};
                rangeTownshipMap = buildRangeTownshipMap(townshipRangeMap);
                if (sectionSelect) {
                    renderSelectOptions(sectionSelect, Array.isArray(payload.sections) ? payload.sections : [], String(source.col02varchar || "").trim());
                }
                allTownshipOptions = Array.isArray(payload.townshipOptions) ? payload.townshipOptions.slice() : [];
                allRangeOptions = Array.isArray(payload.rangeOptions) ? payload.rangeOptions.slice() : [];
                syncTownshipRangeOptions(String(source.col03varchar || "").trim(), String(source.col04varchar || "").trim(), "");
            };
            const renderQuarterChips = () => {
                if (!quarterChips) return;
                quarterChips.innerHTML = quarters.map((q, idx) => `
                    <span class="badge text-bg-info d-inline-flex align-items-center gap-1">
                        ${esc(q)}
                        <button type="button" class="btn btn-sm btn-link text-white p-0 border-0" data-dqc-int-quarter-rm="${idx}">x</button>
                    </span>
                `).join("");
            };
            const setTab = (tab) => {
                const t = String(tab || "additions");
                if (paneAdditions) paneAdditions.hidden = t !== "additions";
                if (paneSTR) paneSTR.hidden = t !== "str";
                if (paneQuarter) paneQuarter.hidden = t !== "quarter";
                if (paneFreeForm) paneFreeForm.hidden = t !== "free_form";
                if (paneSelectLegal) paneSelectLegal.hidden = t !== "select_legal";
                if (tabAdditions) tabAdditions.classList.toggle("active", t === "additions");
                if (tabSTR) tabSTR.classList.toggle("active", t === "str");
                if (tabQuarter) tabQuarter.classList.toggle("active", t === "quarter");
                if (tabFreeForm) tabFreeForm.classList.toggle("active", t === "free_form");
                if (tabSelectLegal) tabSelectLegal.classList.toggle("active", t === "select_legal");
            };
            const getFreeFormLegalValue = () => {
                const selected = integratedEditor.querySelector('input[name="dqcIntFreeFormLegal"]:checked');
                return selected ? String(selected.value || "") : "";
            };
            const setFreeFormLegalValue = (value) => {
                const normalized = String(value || "").trim();
                const allowed = ["No Legal Description", "Incomplete Legal Description", "Not in County"];
                const target = allowed.includes(normalized) ? normalized : "";
                integratedEditor.querySelectorAll('input[name="dqcIntFreeFormLegal"]').forEach((el) => {
                    const input = el;
                    input.checked = String(input.value || "") === target;
                });
                if (!target) {
                    const emptyInput = integratedEditor.querySelector('input[name="dqcIntFreeFormLegal"][value=""]');
                    if (emptyInput) emptyInput.checked = true;
                }
            };
            const applyRowValues = (picked) => {
                if (!picked) return;
                selectedLegalRowId = String(picked.legal_row_id || "").trim();
                const blockEl = document.getElementById("dqcIntBlock");
                const lotEl = document.getElementById("dqcIntLot");
                if (sectionSelect) sectionSelect.value = String(picked.col02varchar || "").trim();
                syncTownshipRangeOptions(String(picked.col03varchar || "").trim(), String(picked.col04varchar || "").trim(), "");
                if (additionInput) additionInput.value = String(picked.col05varchar || "").trim();
                if (blockEl) blockEl.value = String(picked.col06varchar || "").trim();
                if (lotEl) lotEl.value = String(picked.col07varchar || "").trim();
                quarters = String(picked.col08varchar || "")
                    .split(/[,\s]+/)
                    .map((x) => String(x || "").trim().toUpperCase())
                    .filter(Boolean);
                renderQuarterChips();
                setFreeFormLegalValue(String(picked.free_form_legal || ""));
                if (selectedLegalMeta) selectedLegalMeta.textContent = `Selected Legal: #${selectedLegalRowId}`;
                if (legalList) {
                    legalList.querySelectorAll("[data-dqc-int-legal-id]").forEach((el) => {
                        el.classList.toggle("active", String(el.getAttribute("data-dqc-int-legal-id") || "") === selectedLegalRowId);
                    });
                }
            };
            const renderLegalList = () => {
                if (!legalList) return;
                if (!legalRows.length) {
                    legalList.innerHTML = `<div class="small text-muted">No associated legal rows found.</div>`;
                    return;
                }
                legalList.innerHTML = legalRows.map((item) => {
                    const id = String(item.legal_row_id || "").trim();
                    const isActive = id === selectedLegalRowId;
                    const summary = `Sec ${String(item.col02varchar || "-").trim() || "-"} · T ${String(item.col03varchar || "-").trim() || "-"} · R ${String(item.col04varchar || "-").trim() || "-"} · Add ${String(item.col05varchar || "-").trim() || "-"}`;
                    return `
                        <button type="button" class="addons-mii-row ${isActive ? "active" : ""}" data-dqc-int-legal-id="${esc(id)}">
                            <div class="d-flex justify-content-between align-items-center gap-2">
                                <span class="fw-semibold">Legal #${esc(id)}</span>
                                <span class="badge ${Number(item.is_fixed || 0) === 1 ? "text-bg-success" : "text-bg-secondary"}">${Number(item.is_fixed || 0) === 1 ? "fixed" : "pending"}</span>
                            </div>
                            <div class="small text-muted mt-1">${esc(summary)}</div>
                        </button>
                    `;
                }).join("");
            };
            const loadRelatedLegals = async () => {
                if (!legalList) return;
                if (contextRoute) {
                    const payload = await api(`/api/addons/apps/${encodeURIComponent(addonId)}/${contextRoute}`, "GET", null, {
                        addon_id: addonId,
                        addon_type: addonType,
                        addon_action: relatedLegalsAction,
                    });
                    legalRows = Array.isArray(payload.items) ? payload.items : [];
                    renderLegalList();
                    let picked = null;
                    const initialFromPayload = String(payload.initial_legal_row_id || "").trim();
                    if (initialFromPayload) picked = legalRows.find((x) => String(x.legal_row_id || "").trim() === initialFromPayload) || null;
                    if (!picked && pickInitialLegalRow) picked = pickInitialLegalRow(legalRows) || null;
                    if (!picked) picked = legalRows[0] || null;
                    applyRowValues(picked);
                    return;
                }
                if (!headerFileKey || !keyValue) {
                    legalRows = [];
                    renderLegalList();
                    return;
                }
                const params = new URLSearchParams();
                params.set("header_file_key", headerFileKey);
                params.set("col01varchar", keyValue);
                const payload = await api(`/api/addons/apps/${encodeURIComponent(addonId)}/fix-legal-type-others/related-legals?${params.toString()}`, "GET", null, {
                    addon_id: addonId,
                    addon_type: addonType,
                    addon_action: relatedLegalsAction,
                });
                legalRows = Array.isArray(payload.items) ? payload.items : [];
                renderLegalList();
                let picked = legalRows.find((x) => String(x.legal_row_id || "").trim() === selectedLegalRowId) || null;
                if (!picked && pickInitialLegalRow) picked = pickInitialLegalRow(legalRows) || null;
                if (!picked) picked = legalRows[0] || null;
                applyRowValues(picked);
            };
            if (tabAdditions) tabAdditions.addEventListener("click", () => setTab("additions"));
            if (tabSTR) tabSTR.addEventListener("click", () => setTab("str"));
            if (tabQuarter) tabQuarter.addEventListener("click", () => setTab("quarter"));
            if (tabFreeForm) tabFreeForm.addEventListener("click", () => setTab("free_form"));
            if (tabSelectLegal) tabSelectLegal.addEventListener("click", () => setTab("select_legal"));
            if (townshipSelect) {
                townshipSelect.addEventListener("change", () => {
                    syncTownshipRangeOptions(String(townshipSelect.value || "").trim(), String(rangeSelect ? rangeSelect.value || "" : "").trim(), "township");
                });
            }
            if (rangeSelect) {
                rangeSelect.addEventListener("change", () => {
                    syncTownshipRangeOptions(String(townshipSelect ? townshipSelect.value || "" : "").trim(), String(rangeSelect.value || "").trim(), "range");
                });
            }
            if (additionInput) {
                additionInput.addEventListener("input", () => {
                    const val = String(additionInput.value || "").trim();
                    if (addSearchTimer) window.clearTimeout(addSearchTimer);
                    addSearchTimer = window.setTimeout(() => {
                        loadAdditions(val).catch((err) => setBanner(err.message, "danger"));
                    }, 180);
                });
                additionInput.addEventListener("focus", () => {
                    if (additions.length) {
                        renderAdditionResults();
                        return;
                    }
                    loadAdditions("").catch((err) => setBanner(err.message, "danger"));
                });
            }
            if (additionBrowseBtn) {
                additionBrowseBtn.addEventListener("click", () => {
                    loadAdditions("").catch((err) => setBanner(err.message, "danger"));
                });
            }
            if (additionHideBtn) additionHideBtn.addEventListener("click", hideAdditionResults);
            if (additionResults) {
                additionResults.addEventListener("click", (event) => {
                    const btn = event.target.closest("[data-dqc-int-addition-idx]");
                    if (!btn || !additionInput) return;
                    const idx = Number(btn.getAttribute("data-dqc-int-addition-idx"));
                    if (!Number.isFinite(idx) || idx < 0 || idx >= additions.length) return;
                    const picked = additions[idx] || {};
                    additionInput.value = String(picked.name || "").trim();
                    hideAdditionResults();
                });
            }
            if (legalList) {
                legalList.addEventListener("click", (event) => {
                    const btn = event.target.closest("[data-dqc-int-legal-id]");
                    if (!btn) return;
                    const id = String(btn.getAttribute("data-dqc-int-legal-id") || "").trim();
                    const picked = legalRows.find((x) => String(x.legal_row_id || "").trim() === id) || null;
                    applyRowValues(picked);
                });
            }
            const tryAddQuarterFromSelection = async () => {
                const val = String((quarterSelect || {}).value || "").trim().toUpperCase();
                if (quarterSelect) quarterSelect.value = "";
                if (!val) return;
                if (quarters.includes(val)) return;
                if (quarters.length > 0) {
                    const confirmed = await popupConfirm(
                        "This row already has a quarter section. Are you sure you want to add another?",
                        "Add Another Quarter Section",
                    );
                    if (!confirmed) return;
                }
                quarters.push(val);
                renderQuarterChips();
            };
            if (quarterAddBtn) {
                quarterAddBtn.addEventListener("click", () => {
                    tryAddQuarterFromSelection().catch((err) => setBanner(err.message, "danger"));
                });
            }
            if (quarterSelect) {
                quarterSelect.addEventListener("change", () => {
                    tryAddQuarterFromSelection().catch((err) => setBanner(err.message, "danger"));
                });
            }
            if (quarterChips) {
                quarterChips.addEventListener("click", (event) => {
                    const btn = event.target.closest("[data-dqc-int-quarter-rm]");
                    if (!btn) return;
                    const idx = Number(btn.getAttribute("data-dqc-int-quarter-rm"));
                    if (!Number.isFinite(idx) || idx < 0 || idx >= quarters.length) return;
                    quarters.splice(idx, 1);
                    renderQuarterChips();
                });
            }
            renderQuarterChips();
            setFreeFormLegalValue(String(source.free_form_legal || ""));
            setTab("additions");
            hideAdditionResults();
            loadReferenceData()
                .then(loadRelatedLegals)
                .catch((err) => setBanner(err.message, "danger"));
            applyBtn.addEventListener("click", () => {
                if (!submitAction) return;
                const section = String((document.getElementById("dqcIntSection") || {}).value || "").trim();
                const township = String((document.getElementById("dqcIntTownship") || {}).value || "").trim();
                const range = String((document.getElementById("dqcIntRange") || {}).value || "").trim();
                const addition = String((document.getElementById("dqcIntAddition") || {}).value || "").trim();
                const block = String((document.getElementById("dqcIntBlock") || {}).value || "").trim();
                const lot = String((document.getElementById("dqcIntLot") || {}).value || "").trim();
                const quarter = quarters.join(", ").trim();
                const free_form_legal = getFreeFormLegalValue();
                submitAction(
                    "apply",
                    { section, township, range, addition, block, lot, quarter, free_form_legal, add_additional_record: false },
                    applyAction,
                    selectedLegalRowId,
                ).catch((err) => setBanner(err.message, "danger"));
            });
            if (addLegalBtn) {
                addLegalBtn.addEventListener("click", async () => {
                    if (!submitAction) return;
                    const confirmed = await popupConfirm(
                        "Insert another legal record for this same file/key using the current values?",
                        "Add Additional Legal Record",
                    );
                    if (!confirmed) return;
                    const section = String((document.getElementById("dqcIntSection") || {}).value || "").trim();
                    const township = String((document.getElementById("dqcIntTownship") || {}).value || "").trim();
                    const range = String((document.getElementById("dqcIntRange") || {}).value || "").trim();
                    const addition = String((document.getElementById("dqcIntAddition") || {}).value || "").trim();
                    const block = String((document.getElementById("dqcIntBlock") || {}).value || "").trim();
                    const lot = String((document.getElementById("dqcIntLot") || {}).value || "").trim();
                    const quarter = quarters.join(", ").trim();
                    const free_form_legal = getFreeFormLegalValue();
                    submitAction(
                        "apply",
                        { section, township, range, addition, block, lot, quarter, free_form_legal, add_additional_record: true },
                        addAdditionalAction,
                        selectedLegalRowId,
                    ).catch((err) => setBanner(err.message, "danger"));
                });
            }
        }
        async function undoLastChange() {
            const row = selectedItem();
            const normalizedFixedNote = String((row && row.fixed_note) || "").trim().toLowerCase();
            const preferMatchAllGroup = Boolean(
                row
                && !row.__integrated
                && (activeTable === "legal" || activeTable === "record_series")
                && normalizedFixedNote === "match_all_same"
            );
            const confirmed = await popupConfirm(
                preferMatchAllGroup
                    ? "This will undo the full Mark All As Same group that affected the selected row."
                    : "This will undo the most recent DQ change for the current working county and job scope.",
                {
                    title: "Undo Last Change?",
                    confirmText: "Undo Change",
                    cancelText: "Cancel",
                }
            );
            if (!confirmed) return;
            await withProcessingPopup(
                "Undoing Last Change",
                "Restoring the most recent DQ update. Please wait until the undo finishes.",
                async () => {
                    const requestBody = {};
                    if (preferMatchAllGroup && row && !row.__integrated) {
                        requestBody.table = activeTable;
                        requestBody.item_id = row.id;
                        requestBody.source_row_id = row.source_row_id;
                        requestBody.prefer_match_all_group = true;
                    }
                    const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/undo-last`, "POST", requestBody, {
                        addon_id: app.id,
                        addon_type: app.type,
                        addon_action: "dqc_undo_last_change",
                    });
                    setBanner(
                        payload.message || "Last DQ change undone.",
                        payload && payload.rolled_back === false ? "warning" : "success",
                    );
                    await loadErrorTypes();
                    await loadIssues();
                    await refreshPendingBadgeForActiveTable();
                    queueResizeLayout();
                }
            );
        }
        function bindIntegratedEditorHandlers(row) {
            if (!row || !row.__integrated) return;
            const spec = row.__integrated.spec;
            if (spec.type === "fix_legal_type_others") {
                const applyBtn = document.getElementById("dqcIntApplyBtn");
                const source = row.__integrated.row || {};
                const tabAdditions = document.getElementById("dqcIntTabAdditions");
                const tabSTR = document.getElementById("dqcIntTabSTR");
                const tabQuarter = document.getElementById("dqcIntTabQuarter");
                const tabFreeForm = document.getElementById("dqcIntTabFreeForm");
                const tabSelectLegal = document.getElementById("dqcIntTabSelectLegal");
                const paneAdditions = document.getElementById("dqcIntPaneAdditions");
                const paneSTR = document.getElementById("dqcIntPaneSTR");
                const paneQuarter = document.getElementById("dqcIntPaneQuarter");
                const paneFreeForm = document.getElementById("dqcIntPaneFreeForm");
                const paneSelectLegal = document.getElementById("dqcIntPaneSelectLegal");
                const legalList = document.getElementById("dqcIntLegalList");
                const selectedLegalMeta = document.getElementById("dqcIntSelectedLegalMeta");
                const quarterSelect = document.getElementById("dqcIntQuarterSelect");
                const quarterAddBtn = document.getElementById("dqcIntQuarterAddBtn");
                const quarterChips = document.getElementById("dqcIntQuarterChips");
                const addLegalBtn = document.getElementById("dqcIntAddLegalBtn");
                const sectionSelect = document.getElementById("dqcIntSection");
                const townshipSelect = document.getElementById("dqcIntTownship");
                const rangeSelect = document.getElementById("dqcIntRange");
                const additionInput = document.getElementById("dqcIntAddition");
                const additionBrowseBtn = document.getElementById("dqcIntAdditionBrowseBtn");
                const additionResults = document.getElementById("dqcIntAdditionResults");
                const additionHideBtn = document.getElementById("dqcIntAdditionHideBtn");
                if (!applyBtn) return;
                let selectedLegalRowId = String(source.legal_row_id || row.__integrated.row_id || "").trim();
                let quarters = String(source.col08varchar || "")
                    .split(/[,\s]+/)
                    .map((x) => String(x || "").trim().toUpperCase())
                    .filter(Boolean);
                let legalRows = [];
                let additions = [];
                let addSearchTimer = null;
                let townshipRangeMap = {};
                let rangeTownshipMap = {};
                let allRangeOptions = [];
                let allTownshipOptions = [];
                const hideAdditionResults = () => {
                    if (additionResults) additionResults.hidden = true;
                    if (additionHideBtn) additionHideBtn.hidden = true;
                };
                const showAdditionResults = () => {
                    if (additionResults) additionResults.hidden = false;
                    if (additionHideBtn) additionHideBtn.hidden = false;
                };
                const renderAdditionResults = () => {
                    if (!additionResults) return;
                    if (!additions.length) {
                        showAdditionResults();
                        additionResults.innerHTML = `<div class="small text-muted">No matches found.</div>`;
                        return;
                    }
                    showAdditionResults();
                    additionResults.innerHTML = additions.map((entry, idx) => {
                        const activeTag = Number(entry.is_active || 0) === 1
                            ? `<span class="badge text-bg-success">Active</span>`
                            : `<span class="badge text-bg-secondary">Inactive</span>`;
                        const desc = String(entry.description || "").trim();
                        return `
                            <button type="button" class="addons-itc-search-row" data-dqc-int-addition-idx="${idx}">
                                <div class="d-flex flex-wrap gap-1 align-items-center">
                                    <strong>${esc(entry.name || "")}</strong>
                                    ${activeTag}
                                </div>
                                ${desc ? `<div class="small text-muted mt-1">${esc(desc)}</div>` : ""}
                            </button>
                        `;
                    }).join("");
                };
                const loadAdditions = async (query) => {
                    const q = new URLSearchParams();
                    if (query) q.set("q", query);
                    q.set("limit", "2000");
                    const payload = await api(`/api/addons/apps/${encodeURIComponent(row.__integrated.addon_id)}/fix-legal-type-others/search-keli-additions?${q.toString()}`, "GET", null, {
                        addon_id: row.__integrated.addon_id,
                        addon_type: row.__integrated.addon_type,
                        addon_action: "dqc_integrated_search_legal_other_additions",
                    });
                    additions = Array.isArray(payload.items) ? payload.items : [];
                    renderAdditionResults();
                };
                const syncTownshipRangeOptions = (townshipValue, rangeValue, changedField = "") => {
                    if (!townshipSelect || !rangeSelect) return;
                    const t = String(townshipValue || "").trim();
                    const r = String(rangeValue || "").trim();
                    const rangesForTownship = (t && Array.isArray(townshipRangeMap[t])) ? townshipRangeMap[t].slice() : [];
                    const townshipsForRange = (r && Array.isArray(rangeTownshipMap[r])) ? rangeTownshipMap[r].slice() : [];
                    const validPair = t && r
                        ? (Array.isArray(townshipRangeMap[t]) && townshipRangeMap[t].includes(r))
                        : true;
                    let allowedTownships = allTownshipOptions.slice();
                    let allowedRanges = allRangeOptions.slice();
                    let nextTownship = t;
                    let nextRange = r;
                    if (t && !r) {
                        allowedRanges = rangesForTownship;
                    } else if (!t && r) {
                        allowedTownships = townshipsForRange;
                    } else if (t && r && validPair) {
                        allowedTownships = townshipsForRange.length ? townshipsForRange : allTownshipOptions.slice();
                        allowedRanges = rangesForTownship.length ? rangesForTownship : allRangeOptions.slice();
                    } else if (t && r) {
                        if (changedField === "range") {
                            allowedTownships = townshipsForRange;
                            nextTownship = townshipsForRange.includes(t) ? t : "";
                        } else {
                            allowedRanges = rangesForTownship;
                            nextRange = rangesForTownship.includes(r) ? r : "";
                        }
                    }
                    townshipSelect.innerHTML = [`<option value=""></option>`, ...allowedTownships.map((x) => `<option value="${esc(x)}">${esc(x)}</option>`)].join("");
                    rangeSelect.innerHTML = [`<option value=""></option>`, ...allowedRanges.map((x) => `<option value="${esc(x)}">${esc(x)}</option>`)].join("");
                    townshipSelect.value = nextTownship && allowedTownships.includes(nextTownship) ? nextTownship : "";
                    rangeSelect.value = nextRange && allowedRanges.includes(nextRange) ? nextRange : "";
                };
                const loadReferenceData = async () => {
                    const payload = await api(`/api/addons/apps/${encodeURIComponent(row.__integrated.addon_id)}/fix-legal-type-others/reference-data`, "GET", null, {
                        addon_id: row.__integrated.addon_id,
                        addon_type: row.__integrated.addon_type,
                        addon_action: "dqc_integrated_legal_other_reference_data",
                    });
                    const sections = Array.isArray(payload.sections) ? payload.sections : [];
                    const townships = Array.isArray(payload.township_options) ? payload.township_options : [];
                    const ranges = Array.isArray(payload.range_options) ? payload.range_options : [];
                    townshipRangeMap = payload.township_range_map && typeof payload.township_range_map === "object"
                        ? payload.township_range_map
                        : {};
                    rangeTownshipMap = {};
                    Object.keys(townshipRangeMap).forEach((township) => {
                        const rs = Array.isArray(townshipRangeMap[township]) ? townshipRangeMap[township] : [];
                        rs.forEach((rng) => {
                            if (!rangeTownshipMap[rng]) rangeTownshipMap[rng] = [];
                            if (!rangeTownshipMap[rng].includes(township)) rangeTownshipMap[rng].push(township);
                        });
                    });
                    if (sectionSelect) {
                        sectionSelect.innerHTML = [`<option value=""></option>`, ...sections.map((x) => `<option value="${esc(x)}">${esc(x)}</option>`)].join("");
                    }
                    allTownshipOptions = townships.slice();
                    allRangeOptions = ranges.slice();
                    syncTownshipRangeOptions(String(source.col03varchar || ""), String(source.col04varchar || ""), "");
                    if (sectionSelect) sectionSelect.value = String(source.col02varchar || "").trim();
                };
                const renderQuarterChips = () => {
                    if (!quarterChips) return;
                    quarterChips.innerHTML = quarters.map((q, idx) => `
                        <span class="badge text-bg-info d-inline-flex align-items-center gap-1">
                            ${esc(q)}
                            <button type="button" class="btn btn-sm btn-link text-white p-0 border-0" data-dqc-int-quarter-rm="${idx}">x</button>
                        </span>
                    `).join("");
                };
                const setTab = (tab) => {
                    const t = String(tab || "additions");
                    if (paneAdditions) paneAdditions.hidden = t !== "additions";
                    if (paneSTR) paneSTR.hidden = t !== "str";
                    if (paneQuarter) paneQuarter.hidden = t !== "quarter";
                    if (paneFreeForm) paneFreeForm.hidden = t !== "free_form";
                    if (paneSelectLegal) paneSelectLegal.hidden = t !== "select_legal";
                    if (tabAdditions) tabAdditions.classList.toggle("active", t === "additions");
                    if (tabSTR) tabSTR.classList.toggle("active", t === "str");
                    if (tabQuarter) tabQuarter.classList.toggle("active", t === "quarter");
                    if (tabFreeForm) tabFreeForm.classList.toggle("active", t === "free_form");
                    if (tabSelectLegal) tabSelectLegal.classList.toggle("active", t === "select_legal");
                };
                const getFreeFormLegalValue = () => {
                    const selected = integratedEditor.querySelector('input[name="dqcIntFreeFormLegal"]:checked');
                    return selected ? String(selected.value || "") : "";
                };
                const setFreeFormLegalValue = (value) => {
                    const normalized = String(value || "").trim();
                    const allowed = ["No Legal Description", "Incomplete Legal Description", "Not in County"];
                    const target = allowed.includes(normalized) ? normalized : "";
                    integratedEditor.querySelectorAll('input[name="dqcIntFreeFormLegal"]').forEach((el) => {
                        const input = el;
                        input.checked = String(input.value || "") === target;
                    });
                    if (!target) {
                        const emptyInput = integratedEditor.querySelector('input[name="dqcIntFreeFormLegal"][value=""]');
                        if (emptyInput) emptyInput.checked = true;
                    }
                };
                const applyRowValues = (picked) => {
                    if (!picked) return;
                    selectedLegalRowId = String(picked.legal_row_id || "").trim();
                    const blockEl = document.getElementById("dqcIntBlock");
                    const lotEl = document.getElementById("dqcIntLot");
                    if (sectionSelect) sectionSelect.value = String(picked.col02varchar || "").trim();
                    syncTownshipRangeOptions(String(picked.col03varchar || ""), String(picked.col04varchar || ""), "");
                    if (additionInput) additionInput.value = String(picked.col05varchar || "").trim();
                    if (blockEl) blockEl.value = String(picked.col06varchar || "").trim();
                    if (lotEl) lotEl.value = String(picked.col07varchar || "").trim();
                    quarters = String(picked.col08varchar || "")
                        .split(/[,\s]+/)
                        .map((x) => String(x || "").trim().toUpperCase())
                        .filter(Boolean);
                    renderQuarterChips();
                    setFreeFormLegalValue(String(picked.free_form_legal || ""));
                    if (selectedLegalMeta) selectedLegalMeta.textContent = `Selected Legal: #${selectedLegalRowId}`;
                    if (legalList) {
                        legalList.querySelectorAll("[data-dqc-int-legal-id]").forEach((el) => {
                            el.classList.toggle("active", String(el.getAttribute("data-dqc-int-legal-id") || "") === selectedLegalRowId);
                        });
                    }
                };
                const renderLegalList = () => {
                    if (!legalList) return;
                    if (!legalRows.length) {
                        legalList.innerHTML = `<div class="small text-muted">No associated legal rows found.</div>`;
                        return;
                    }
                    legalList.innerHTML = legalRows.map((item) => {
                        const id = String(item.legal_row_id || "").trim();
                        const isActive = id === selectedLegalRowId;
                        const type = String(item.legal_type || "").trim() || "(blank)";
                        const freeForm = String(item.free_form_legal || "").trim() || "(blank)";
                        const summary = `Sec ${String(item.col02varchar || "-").trim() || "-"} · T ${String(item.col03varchar || "-").trim() || "-"} · R ${String(item.col04varchar || "-").trim() || "-"} · Add ${String(item.col05varchar || "-").trim() || "-"}`;
                        return `
                            <button type="button" class="addons-mii-row ${isActive ? "active" : ""}" data-dqc-int-legal-id="${esc(id)}">
                                <div class="d-flex justify-content-between align-items-center gap-2">
                                    <span class="fw-semibold">Legal #${esc(id)} · ${esc(type)}</span>
                                    <span class="badge ${Number(item.is_fixed || 0) === 1 ? "text-bg-success" : "text-bg-secondary"}">${Number(item.is_fixed || 0) === 1 ? "fixed" : "pending"}</span>
                                </div>
                                <div class="small text-muted mt-1">${esc(summary)}</div>
                                <div class="small text-muted">free_form=${esc(freeForm)}</div>
                            </button>
                        `;
                    }).join("");
                };
                const loadRelatedLegals = async () => {
                    if (!legalList) return;
                    const headerFileKey = String(source.header_file_key || "").trim();
                    const key = String(source.col01varchar || "").trim();
                    if (!headerFileKey || !key) {
                        legalRows = [];
                        renderLegalList();
                        return;
                    }
                    const params = new URLSearchParams();
                    params.set("header_file_key", headerFileKey);
                    params.set("col01varchar", key);
                    const payload = await api(`/api/addons/apps/${encodeURIComponent(row.__integrated.addon_id)}/fix-legal-type-others/related-legals?${params.toString()}`, "GET", null, {
                        addon_id: row.__integrated.addon_id,
                        addon_type: row.__integrated.addon_type,
                        addon_action: "dqc_integrated_legal_other_related_legals",
                    });
                    legalRows = Array.isArray(payload.items) ? payload.items : [];
                    renderLegalList();
                    const picked = legalRows.find((x) => String(x.legal_row_id || "").trim() === selectedLegalRowId) || legalRows[0] || null;
                    applyRowValues(picked);
                };
                if (tabAdditions) tabAdditions.addEventListener("click", () => setTab("additions"));
                if (tabSTR) tabSTR.addEventListener("click", () => setTab("str"));
                if (tabQuarter) tabQuarter.addEventListener("click", () => setTab("quarter"));
                if (tabFreeForm) tabFreeForm.addEventListener("click", () => setTab("free_form"));
                if (tabSelectLegal) tabSelectLegal.addEventListener("click", () => setTab("select_legal"));
                if (townshipSelect) {
                    townshipSelect.addEventListener("change", () => {
                        syncTownshipRangeOptions(String(townshipSelect.value || ""), String(rangeSelect ? rangeSelect.value : ""), "township");
                    });
                }
                if (rangeSelect) {
                    rangeSelect.addEventListener("change", () => {
                        syncTownshipRangeOptions(String(townshipSelect ? townshipSelect.value : ""), String(rangeSelect.value || ""), "range");
                    });
                }
                if (additionInput) {
                    additionInput.addEventListener("input", () => {
                        const val = String(additionInput.value || "").trim();
                        if (addSearchTimer) window.clearTimeout(addSearchTimer);
                        addSearchTimer = window.setTimeout(() => {
                            loadAdditions(val).catch((err) => setBanner(err.message, "danger"));
                        }, 180);
                    });
                    additionInput.addEventListener("focus", () => {
                        if (additions.length) {
                            renderAdditionResults();
                            return;
                        }
                        loadAdditions("").catch((err) => setBanner(err.message, "danger"));
                    });
                }
                if (additionBrowseBtn) {
                    additionBrowseBtn.addEventListener("click", () => {
                        loadAdditions("").catch((err) => setBanner(err.message, "danger"));
                    });
                }
                if (additionHideBtn) additionHideBtn.addEventListener("click", hideAdditionResults);
                if (additionResults) {
                    additionResults.addEventListener("click", (event) => {
                        const btn = event.target.closest("[data-dqc-int-addition-idx]");
                        if (!btn || !additionInput) return;
                        const idx = Number(btn.getAttribute("data-dqc-int-addition-idx"));
                        if (!Number.isFinite(idx) || idx < 0 || idx >= additions.length) return;
                        const picked = additions[idx] || {};
                        additionInput.value = String(picked.name || "").trim();
                        hideAdditionResults();
                    });
                }
                if (legalList) {
                    legalList.addEventListener("click", (event) => {
                        const btn = event.target.closest("[data-dqc-int-legal-id]");
                        if (!btn) return;
                        const id = String(btn.getAttribute("data-dqc-int-legal-id") || "").trim();
                        const picked = legalRows.find((x) => String(x.legal_row_id || "").trim() === id) || null;
                        applyRowValues(picked);
                    });
                }
                const tryAddQuarterFromSelection = async () => {
                    const val = String((quarterSelect || {}).value || "").trim().toUpperCase();
                    if (quarterSelect) quarterSelect.value = "";
                    if (!val) return;
                    if (quarters.includes(val)) return;
                    if (quarters.length > 0) {
                        const confirmed = await popupConfirm(
                            "This row already has a quarter section. Are you sure you want to add another?",
                            "Add Another Quarter Section",
                        );
                        if (!confirmed) return;
                    }
                    quarters.push(val);
                    renderQuarterChips();
                };
                if (quarterAddBtn) {
                    quarterAddBtn.addEventListener("click", () => {
                        tryAddQuarterFromSelection().catch((err) => setBanner(err.message, "danger"));
                    });
                }
                if (quarterSelect) {
                    quarterSelect.addEventListener("change", () => {
                        tryAddQuarterFromSelection().catch((err) => setBanner(err.message, "danger"));
                    });
                }
                if (quarterChips) {
                    quarterChips.addEventListener("click", (event) => {
                        const btn = event.target.closest("[data-dqc-int-quarter-rm]");
                        if (!btn) return;
                        const idx = Number(btn.getAttribute("data-dqc-int-quarter-rm"));
                        if (!Number.isFinite(idx) || idx < 0 || idx >= quarters.length) return;
                        quarters.splice(idx, 1);
                        renderQuarterChips();
                    });
                }
                renderQuarterChips();
                setFreeFormLegalValue(String(source.free_form_legal || ""));
                setTab("additions");
                hideAdditionResults();
                loadReferenceData()
                    .then(loadRelatedLegals)
                    .catch((err) => setBanner(err.message, "danger"));
                applyBtn.addEventListener("click", () => {
                    const section = String((document.getElementById("dqcIntSection") || {}).value || "").trim();
                    const township = String((document.getElementById("dqcIntTownship") || {}).value || "").trim();
                    const range = String((document.getElementById("dqcIntRange") || {}).value || "").trim();
                    const addition = String((document.getElementById("dqcIntAddition") || {}).value || "").trim();
                    const block = String((document.getElementById("dqcIntBlock") || {}).value || "").trim();
                    const lot = String((document.getElementById("dqcIntLot") || {}).value || "").trim();
                    const quarter = quarters.join(", ").trim();
                    const free_form_legal = getFreeFormLegalValue();
                    submitIntegratedAction(
                        "apply",
                        { section, township, range, addition, block, lot, quarter, free_form_legal, add_additional_record: false },
                        "dqc_integrated_legal_other_apply",
                        selectedLegalRowId,
                    ).catch((err) => setBanner(err.message, "danger"));
                });
                if (addLegalBtn) {
                    addLegalBtn.addEventListener("click", async () => {
                        const confirmed = await popupConfirm(
                            "Insert another legal record for this same file/key using the current values?",
                            "Add Additional Legal Record",
                        );
                        if (!confirmed) return;
                        const section = String((document.getElementById("dqcIntSection") || {}).value || "").trim();
                        const township = String((document.getElementById("dqcIntTownship") || {}).value || "").trim();
                        const range = String((document.getElementById("dqcIntRange") || {}).value || "").trim();
                        const addition = String((document.getElementById("dqcIntAddition") || {}).value || "").trim();
                        const block = String((document.getElementById("dqcIntBlock") || {}).value || "").trim();
                        const lot = String((document.getElementById("dqcIntLot") || {}).value || "").trim();
                        const quarter = quarters.join(", ").trim();
                        const free_form_legal = getFreeFormLegalValue();
                        submitIntegratedAction(
                            "apply",
                            { section, township, range, addition, block, lot, quarter, free_form_legal, add_additional_record: true },
                            "dqc_integrated_legal_other_additional",
                            selectedLegalRowId,
                        ).catch((err) => setBanner(err.message, "danger"));
                    });
                }
                return;
            }
            if (spec.type === "missing_grantor_grantee_names") {
                const applyBtn = document.getElementById("dqcIntApplyBtn");
                const markSameBtn = document.getElementById("dqcIntMarkSameBtn");
                const skipBtn = document.getElementById("dqcIntSkipBtn");
                const addNameBtn = document.getElementById("dqcIntAddNameBtn");
                const tabEditName = document.getElementById("dqcIntTabEditName");
                const tabSelectName = document.getElementById("dqcIntTabSelectName");
                const paneEditName = document.getElementById("dqcIntPaneEditName");
                const paneSelectName = document.getElementById("dqcIntPaneSelectName");
                const nameList = document.getElementById("dqcIntNameList");
                const selectedNameMeta = document.getElementById("dqcIntSelectedNameMeta");
                const source = row.__integrated.row || {};
                let selectedNameRowId = String(source.name_row_id || row.__integrated.row_id || "").trim();
                let nameRows = [];
                const setTab = (tab) => {
                    const t = String(tab || "edit_name");
                    if (paneEditName) paneEditName.hidden = t !== "edit_name";
                    if (paneSelectName) paneSelectName.hidden = t !== "select_name";
                    if (tabEditName) tabEditName.classList.toggle("active", t === "edit_name");
                    if (tabSelectName) tabSelectName.classList.toggle("active", t === "select_name");
                };
                const applyRowValues = (picked) => {
                    if (!picked) return;
                    selectedNameRowId = String(picked.name_row_id || "").trim();
                    const typeEl = document.getElementById("dqcIntType");
                    const nameEl = document.getElementById("dqcIntName");
                    const typeUpper = String(picked.col02varchar || "").trim().toUpperCase();
                    const normalizedType = typeUpper === "GRANTEE" ? "Grantee" : "Grantor";
                    if (typeEl) typeEl.value = normalizedType;
                    if (nameEl) nameEl.value = String(picked.col03varchar || "").trim();
                    if (selectedNameMeta) selectedNameMeta.textContent = `Selected Name: #${selectedNameRowId}`;
                    if (nameList) {
                        nameList.querySelectorAll("[data-dqc-int-name-id]").forEach((el) => {
                            el.classList.toggle("active", String(el.getAttribute("data-dqc-int-name-id") || "") === selectedNameRowId);
                        });
                    }
                };
                const renderNameList = () => {
                    if (!nameList) return;
                    if (!nameRows.length) {
                        nameList.innerHTML = `<div class="small text-muted">No associated names found.</div>`;
                        return;
                    }
                    nameList.innerHTML = nameRows.map((item) => {
                        const id = String(item.name_row_id || "").trim();
                        const isActive = id === selectedNameRowId;
                        const partyUpper = String(item.col02varchar || "").trim().toUpperCase();
                        const party = partyUpper === "GRANTEE" ? "Grantee" : "Grantor";
                        const name = String(item.col03varchar || "").trim() || "(blank)";
                        return `
                            <button type="button" class="addons-mii-row ${isActive ? "active" : ""}" data-dqc-int-name-id="${esc(id)}">
                                <div class="d-flex justify-content-between align-items-center gap-2">
                                    <span class="fw-semibold">Name #${esc(id)} · ${esc(party)}</span>
                                    <span class="badge ${Number(item.is_fixed || 0) === 1 ? "text-bg-success" : "text-bg-secondary"}">${Number(item.is_fixed || 0) === 1 ? "fixed" : "pending"}</span>
                                </div>
                                <div class="small text-muted mt-1">${esc(name)}</div>
                            </button>
                        `;
                    }).join("");
                };
                const loadRelatedNames = async () => {
                    if (!nameList) return;
                    const headerFileKey = String(source.header_file_key || "").trim();
                    const key = String(source.col01varchar || "").trim();
                    if (!headerFileKey || !key) {
                        nameRows = [];
                        renderNameList();
                        return;
                    }
                    const params = new URLSearchParams();
                    params.set("header_file_key", headerFileKey);
                    params.set("col01varchar", key);
                    const payload = await api(`/api/addons/apps/${encodeURIComponent(row.__integrated.addon_id)}/missing-grantor-grantee-names/related-names?${params.toString()}`, "GET", null, {
                        addon_id: row.__integrated.addon_id,
                        addon_type: row.__integrated.addon_type,
                        addon_action: "dqc_integrated_missing_names_related_names",
                    });
                    nameRows = Array.isArray(payload.items) ? payload.items : [];
                    renderNameList();
                    const picked = nameRows.find((x) => String(x.name_row_id || "").trim() === selectedNameRowId) || nameRows[0] || null;
                    applyRowValues(picked);
                };
                const getPayload = () => {
                    const type = String((document.getElementById("dqcIntType") || {}).value || "").trim();
                    const name = String((document.getElementById("dqcIntName") || {}).value || "").trim();
                    return { type, name };
                };
                if (tabEditName) tabEditName.addEventListener("click", () => setTab("edit_name"));
                if (tabSelectName) tabSelectName.addEventListener("click", () => setTab("select_name"));
                if (nameList) {
                    nameList.addEventListener("click", (event) => {
                        const btn = event.target.closest("[data-dqc-int-name-id]");
                        if (!btn) return;
                        const id = String(btn.getAttribute("data-dqc-int-name-id") || "").trim();
                        const picked = nameRows.find((x) => String(x.name_row_id || "").trim() === id) || null;
                        applyRowValues(picked);
                    });
                }
                if (applyBtn) {
                    applyBtn.addEventListener("click", () => submitIntegratedAction(
                        "apply",
                        { ...getPayload(), add_additional_record: false },
                        "dqc_integrated_missing_names_apply",
                        selectedNameRowId,
                    ).catch((err) => setBanner(err.message, "danger")));
                }
                if (addNameBtn) {
                    addNameBtn.addEventListener("click", async () => {
                        const confirmed = await popupConfirm(
                            "Insert another name row for this same file/key using the current values?",
                            "Add Additional Name Record",
                        );
                        if (!confirmed) return;
                        submitIntegratedAction(
                            "apply",
                            { ...getPayload(), add_additional_record: true },
                            "dqc_integrated_missing_names_additional",
                            selectedNameRowId,
                        ).catch((err) => setBanner(err.message, "danger"));
                    });
                }
                if (markSameBtn) {
                    markSameBtn.addEventListener("click", () => submitIntegratedAction(
                        "mark-same",
                        getPayload(),
                        "dqc_integrated_missing_names_mark_same",
                        selectedNameRowId,
                    ).catch((err) => setBanner(err.message, "danger")));
                }
                if (skipBtn) {
                    skipBtn.addEventListener("click", () => submitIntegratedAction(
                        "skip",
                        {},
                        "dqc_integrated_missing_names_skip",
                        selectedNameRowId,
                    ).catch((err) => setBanner(err.message, "danger")));
                }
                setTab("edit_name");
                loadRelatedNames().catch((err) => setBanner(err.message, "danger"));
                return;
            }
        }
        function renderIntegratedEditor(row) {
            resetIntegratedEditor();
            if (!row || !row.__integrated) return;
            const spec = row.__integrated.spec;
            const source = row.__integrated.row || {};
            if (typeof spec.renderEditor === "function") {
                spec.renderEditor({
                    row,
                    source,
                    spec,
                    app,
                    integratedEditor,
                    esc,
                    wireIntegratedLookup,
                    submitIntegratedAction,
                    setBanner,
                    popupAlert,
                    popupConfirm,
                    promptAdditionNeedsAddedName,
                });
                integratedEditor.hidden = false;
                return;
            }
            if (spec.type === "fix_legal_type_others") {
                const quarterTokens = String(source.col08varchar || "")
                    .split(/[,\s]+/)
                    .map((x) => String(x || "").trim().toUpperCase())
                    .filter(Boolean);
                integratedEditor.innerHTML = `
                    <div class="col-12">
                        <ul class="nav nav-tabs nav-sm mb-2">
                            <li class="nav-item"><button id="dqcIntTabAdditions" class="nav-link active py-1 px-2" type="button">Additions</button></li>
                            <li class="nav-item"><button id="dqcIntTabSTR" class="nav-link py-1 px-2" type="button">STR</button></li>
                            <li class="nav-item"><button id="dqcIntTabQuarter" class="nav-link py-1 px-2" type="button">Quarter Section</button></li>
                            <li class="nav-item"><button id="dqcIntTabFreeForm" class="nav-link py-1 px-2" type="button">Free Form Legal</button></li>
                            <li class="nav-item"><button id="dqcIntTabSelectLegal" class="nav-link py-1 px-2" type="button">Select Legal</button></li>
                        </ul>
                    </div>
                    <div id="dqcIntPaneAdditions" class="col-12">
                        <div class="row g-2">
                            <div class="col-md-12">
                                <div class="addons-itc-search-wrap">
                                    <div class="d-flex justify-content-between align-items-center">
                                        <label class="form-label small mb-1" for="dqcIntAddition">Addition</label>
                                        <button id="dqcIntAdditionHideBtn" class="btn btn-outline-secondary btn-sm py-0 px-2" type="button" hidden>Hide</button>
                                    </div>
                                    <div class="input-group input-group-sm">
                                        <input id="dqcIntAddition" class="form-control form-control-sm" type="text" placeholder="Search additions..." value="${esc(String(source.col05varchar || ""))}">
                                        <button id="dqcIntAdditionBrowseBtn" class="btn btn-outline-secondary" type="button" title="Show addition list">
                                            <i class="bi bi-chevron-down"></i>
                                        </button>
                                    </div>
                                    <div id="dqcIntAdditionResults" class="addons-itc-search-results mt-1" hidden></div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <label class="form-label small mb-1" for="dqcIntLot">Lot</label>
                                <input id="dqcIntLot" class="form-control form-control-sm" type="text" value="${esc(String(source.col07varchar || ""))}">
                            </div>
                            <div class="col-md-3">
                                <label class="form-label small mb-1" for="dqcIntBlock">Block</label>
                                <input id="dqcIntBlock" class="form-control form-control-sm" type="text" value="${esc(String(source.col06varchar || ""))}">
                            </div>
                        </div>
                    </div>
                    <div id="dqcIntPaneSTR" class="col-12" hidden>
                        <div class="row g-2">
                            <div class="col-md-4">
                                <label class="form-label small mb-1" for="dqcIntSection">Section</label>
                                <select id="dqcIntSection" class="form-select form-select-sm"></select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small mb-1" for="dqcIntTownship">Township</label>
                                <select id="dqcIntTownship" class="form-select form-select-sm"></select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small mb-1" for="dqcIntRange">Range</label>
                                <select id="dqcIntRange" class="form-select form-select-sm"></select>
                            </div>
                        </div>
                    </div>
                    <div id="dqcIntPaneQuarter" class="col-12" hidden>
                        <div class="row g-2">
                            <div class="col-md-8">
                                <label class="form-label small mb-1" for="dqcIntQuarterSelect">Quarter Section</label>
                                <select id="dqcIntQuarterSelect" class="form-select form-select-sm">
                                    <option value=""></option>
                                    ${["NE","SE","NW","SW","N","S","E","W","N2","S2","E2","W2"].map((q) => `<option value="${q}">${q}</option>`).join("")}
                                </select>
                            </div>
                            <div class="col-md-4 d-flex align-items-end">
                                <button id="dqcIntQuarterAddBtn" class="btn btn-outline-primary btn-sm w-100" type="button">Add Quarter</button>
                            </div>
                            <div class="col-12">
                                <div id="dqcIntQuarterChips" class="d-flex flex-wrap gap-1">
                                    ${quarterTokens.map((q, idx) => `
                                        <span class="badge text-bg-info d-inline-flex align-items-center gap-1">
                                            ${esc(q)}
                                            <button type="button" class="btn btn-sm btn-link text-white p-0 border-0" data-dqc-int-quarter-rm="${idx}">x</button>
                                        </span>
                                    `).join("")}
                                </div>
                            </div>
                        </div>
                    </div>
                    <div id="dqcIntPaneFreeForm" class="col-12" hidden>
                        <div class="row g-2">
                            <div class="col-12">
                                <label class="form-label small mb-1">Free Form Legal</label>
                                <div class="d-flex flex-column gap-1">
                                    <label class="d-flex align-items-center gap-2 small"><input type="radio" name="dqcIntFreeFormLegal" value="No Legal Description">No Legal Description</label>
                                    <label class="d-flex align-items-center gap-2 small"><input type="radio" name="dqcIntFreeFormLegal" value="Incomplete Legal Description">Incomplete Legal Description</label>
                                    <label class="d-flex align-items-center gap-2 small"><input type="radio" name="dqcIntFreeFormLegal" value="Not in County">Not in County</label>
                                    <label class="d-flex align-items-center gap-2 small"><input type="radio" name="dqcIntFreeFormLegal" value="">Empty</label>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div id="dqcIntPaneSelectLegal" class="col-12" hidden>
                        <div class="small text-muted mb-1">Choose which legal row to edit for this record key.</div>
                        <div id="dqcIntSelectedLegalMeta" class="small mb-1">Selected Legal: #${esc(String(source.legal_row_id || ""))}</div>
                        <div id="dqcIntLegalList" class="addons-mii-list" style="max-height: 220px; overflow: auto;"></div>
                    </div>
                    <div class="col-12 d-flex gap-2">
                        <button id="dqcIntApplyBtn" class="btn btn-warning btn-sm" type="button">Apply</button>
                        <button id="dqcIntAddLegalBtn" class="btn btn-outline-warning btn-sm" type="button">Add Additional Legal</button>
                    </div>
                `;
            } else if (spec.type === "missing_grantor_grantee_names") {
                const party = String(source.col02varchar || source.suggested_type || "Grantor");
                integratedEditor.innerHTML = `
                    <div class="col-12">
                        <ul class="nav nav-tabs nav-sm mb-2">
                            <li class="nav-item"><button id="dqcIntTabEditName" class="nav-link active py-1 px-2" type="button">Edit Name</button></li>
                            <li class="nav-item"><button id="dqcIntTabSelectName" class="nav-link py-1 px-2" type="button">Select Name</button></li>
                        </ul>
                    </div>
                    <div id="dqcIntPaneEditName" class="col-12">
                        <div class="row g-2">
                            <div class="col-md-4">
                                <label class="form-label small mb-1" for="dqcIntType">Type</label>
                                <select id="dqcIntType" class="form-select form-select-sm">
                                    <option value="Grantor" ${party.toLowerCase() === "grantor" ? "selected" : ""}>Grantor</option>
                                    <option value="Grantee" ${party.toLowerCase() === "grantee" ? "selected" : ""}>Grantee</option>
                                </select>
                            </div>
                            <div class="col-md-8">
                                <label class="form-label small mb-1" for="dqcIntName">Name</label>
                                <input id="dqcIntName" class="form-control form-control-sm" type="text" value="${esc(String(source.col03varchar || ""))}">
                            </div>
                        </div>
                    </div>
                    <div id="dqcIntPaneSelectName" class="col-12" hidden>
                        <div class="small text-muted mb-1">Choose which name row to edit for this record key.</div>
                        <div id="dqcIntSelectedNameMeta" class="small mb-1">Selected Name: #${esc(String(source.name_row_id || row.__integrated.row_id || ""))}</div>
                        <div id="dqcIntNameList" class="addons-mii-list" style="max-height: 220px; overflow: auto;"></div>
                    </div>
                    <div class="col-12 d-flex gap-2">
                        <button id="dqcIntApplyBtn" class="btn btn-warning btn-sm" type="button">Apply</button>
                        <button id="dqcIntAddNameBtn" class="btn btn-outline-warning btn-sm" type="button">Add Additional Name</button>
                        <button id="dqcIntMarkSameBtn" class="btn btn-outline-info btn-sm" type="button">Mark As Same</button>
                        <button id="dqcIntSkipBtn" class="btn btn-outline-danger btn-sm" type="button">Skip / Delete Blank Pair</button>
                    </div>
                `;
            } else if (spec.type === "missed_indexing_images") {
                integratedEditor.innerHTML = `
                    <div class="col-12">
                        <div class="small text-muted">Missing from index queue item</div>
                        <div class="fw-semibold">${esc(String(source.relative_path || source.file_name || "(unknown file)"))}</div>
                        <div class="small text-muted mt-1">Use footer actions: Mark Fixed = Needs Indexed, Ignore, or Mark Pending.</div>
                    </div>
                `;
            } else if (spec.type === "indexed_images_missing_files") {
                integratedEditor.innerHTML = `
                    <div class="col-12">
                        <div class="small text-muted">Indexed image points to a file that does not exist</div>
                        <div class="fw-semibold">${esc(String(source.relative_path || "(no path)"))}</div>
                        <div class="small text-muted mt-1">Book: ${esc(String(source.book_value || ""))} · Page: ${esc(String(source.page_value || ""))}</div>
                        <div class="small text-muted mt-1">No preview is available for this issue type.</div>
                    </div>
                `;
            } else if (spec.type === "working_images_not_in_source") {
                integratedEditor.innerHTML = `
                    <div class="col-12">
                        <div class="small text-muted">Working folder image does not exist in source set</div>
                        <div class="fw-semibold">${esc(String(source.relative_path || source.file_name || "(unknown file)"))}</div>
                        <div class="small text-muted mt-1">Use footer actions: Mark Fixed (confirmed missing), Ignore, or Mark Pending.</div>
                    </div>
                `;
            }
            integratedEditor.hidden = false;
            bindIntegratedEditorHandlers(row);
        }
        function renderTownshipRangeEditor(row) {
            resetIntegratedEditor();
            if (!row) return;
            integratedEditor.innerHTML = renderLegalTypeOtherEditorMarkup(row);
            integratedEditor.hidden = false;
            bindLegalTypeOtherEditorHandlers({
                source: row,
                addonId: app.id,
                addonType: app.type,
                initialLegalRowId: String(row.integrated_row_id || "").trim(),
                submitAction: (pathSuffix, body, actionLabel, rowIdOverride) => submitLegalTypeOtherStyleActionForTownshipRange(pathSuffix, body, actionLabel, rowIdOverride),
                pickInitialLegalRow: (legalRows) => {
                    const targetLegalRowId = String(row.integrated_row_id || "").trim();
                    const targetTownship = String(row.col03varchar || "").trim();
                    const targetRange = String(row.col04varchar || "").trim();
                    return legalRows.find((entry) => String(entry.legal_row_id || "").trim() === targetLegalRowId)
                        || legalRows.find((entry) => (
                            String(entry.col03varchar || "").trim() === targetTownship
                            && String(entry.col04varchar || "").trim() === targetRange
                        ))
                        || null;
                },
                contextRoute: `data-quality-corrections/items/${encodeURIComponent(row.id)}/township-range-legal-context`,
                searchAdditionsAction: "dqc_township_range_legal_editor_additions",
                relatedLegalsAction: "dqc_township_range_legal_editor_related_legals",
                applyAction: "dqc_township_range_legal_editor_apply",
                addAdditionalAction: "dqc_township_range_legal_editor_additional",
            });
        }
        function showEditOverlay() {
            if (editRecordBtn.disabled) return;
            editOverlay.hidden = false;
        }
        function syncAppPendingBadge(count) {
            const safeCount = Number.isFinite(Number(count)) ? Math.max(0, Number(count)) : 0;
            app.pending_count = safeCount;
            const selected = state.apps.find((x) => x.id === app.id);
            if (selected) selected.pending_count = safeCount;
            const all = state.allApps.find((x) => x.id === app.id);
            if (all) all.pending_count = safeCount;
            renderAppsList();
        }
        function setSelection(item, opts = {}) {
            const preserveMulti = Boolean(opts && opts.preserveMulti);
            if (!item) {
                previewMeta.textContent = "Select an issue from the queue. Ctrl/Cmd+click to multi-select, Shift+click for range.";
                snapshotEl.textContent = "No issue selected.";
                selectedId = null;
                selectedIndex = -1;
                selectionAnchorIndex = -1;
                selectedIds = new Set();
                markFixedBtn.disabled = true;
                markDeleteBtn.disabled = true;
                markInstrumentDeleteBtn.disabled = true;
                restoreInstrumentBtn.disabled = true;
                restoreDeleteBtn.disabled = true;
                ignoreBtn.disabled = true;
                markPendingBtn.disabled = true;
                editRecordBtn.disabled = true;
                hideEditOverlay();
                headerFieldsWrap.hidden = true;
                resetIntegratedEditor();
                applyFieldsBtn.disabled = true;
                markAllSameBtn.hidden = true;
                markAllSameBtn.disabled = true;
                needsInsertBtn.disabled = true;
                dynamicFieldsHost.innerHTML = "";
                activeFieldInputs = [];
                if (inlineViewer && typeof inlineViewer.clear === "function") inlineViewer.clear("No image selected.");
                return;
            }
            selectedId = item.id;
            const selectedKey = String(item.id);
            if (!preserveMulti) selectedIds = new Set([selectedKey]);
            else if (!selectedIds.has(selectedKey)) selectedIds.add(selectedKey);
            const byIdentity = issues.indexOf(item);
            if (byIdentity >= 0) selectedIndex = byIdentity;
            else {
                const byId = issues.findIndex((x) => String(x.id) === String(item.id));
                selectedIndex = byId >= 0 ? byId : -1;
            }
            if (!preserveMulti) selectionAnchorIndex = selectedIndex;
            const selectedRows = selectedItems();
            const selectedCount = selectedRows.length;
            previewMeta.textContent = selectedCount > 1
                ? `${selectedCount} issues selected. Showing primary issue details below.`
                : `${item.error_label || item.error_key || ""} · ${item.file_key || ""} · ${item.col01varchar || ""}`;
            snapshotEl.textContent = item.snapshot || "";
            const isIntegrated = Boolean(item.__integrated);
            const hasStatusEligible = selectedRows.some((row) => {
                if (!row.__integrated) return true;
                return Boolean((((row.__integrated || {}).spec) || {}).supportsStatus);
            });
            const hasDeleteEligible = selectedRows.some((row) => {
                if (!row.__integrated) return true;
                return Boolean((((row.__integrated || {}).spec) || {}).supportsDelete);
            });
            markFixedBtn.disabled = !hasStatusEligible;
            markDeleteBtn.disabled = !hasDeleteEligible;
            const hasInstrumentDeleteEligible = selectedRows.some((row) => {
                if (!row.__integrated) return true;
                return Boolean((((row.__integrated || {}).spec) || {}).supportsInstrumentDelete);
            });
            markInstrumentDeleteBtn.disabled = !hasInstrumentDeleteEligible;
            restoreInstrumentBtn.disabled = !hasInstrumentDeleteEligible;
            restoreDeleteBtn.disabled = !hasDeleteEligible;
            ignoreBtn.disabled = !hasStatusEligible;
            markPendingBtn.disabled = !hasStatusEligible;
            const isHeader = activeTable === "header";
            needsInsertBtn.disabled = !isHeader || selectedCount !== 1;
            const fields = editableFieldsByError[String(item.error_key || "")] || [];
            const usesTownshipRangeLegalEditor = activeTable === "township_range";
            editRecordBtn.disabled = selectedCount !== 1 ? true : (isIntegrated ? false : (usesTownshipRangeLegalEditor ? false : !fields.length));
            if (!fields.length && !isIntegrated && !usesTownshipRangeLegalEditor) hideEditOverlay();
            activeFieldInputs = [];
            dynamicFieldsHost.innerHTML = "";
            resetIntegratedEditor();
            if (selectedCount !== 1) {
                headerFieldsWrap.hidden = true;
                applyFieldsBtn.disabled = true;
                markAllSameBtn.hidden = true;
                markAllSameBtn.disabled = true;
                return;
            }
            if (isIntegrated) {
                headerFieldsWrap.hidden = true;
                applyFieldsBtn.disabled = true;
                markAllSameBtn.hidden = true;
                markAllSameBtn.disabled = true;
                renderIntegratedEditor(item);
                return;
            }
            if (activeTable === "township_range") {
                headerFieldsWrap.hidden = true;
                applyFieldsBtn.disabled = true;
                markAllSameBtn.hidden = true;
                markAllSameBtn.disabled = true;
                renderTownshipRangeEditor(item);
                return;
            }
            if (!fields.length) {
                headerFieldsWrap.hidden = true;
                applyFieldsBtn.disabled = true;
                markAllSameBtn.hidden = true;
                markAllSameBtn.disabled = true;
                return;
            }
            fields.forEach((fieldKey) => {
                const def = editableFieldDefs[fieldKey] || { label: fieldKey, width: "col-md-4" };
                const inputId = `dqcDynamic_${fieldKey}`;
                const wrap = document.createElement("div");
                wrap.className = def.width;
                wrap.innerHTML = `
                    <label class="form-label small mb-1" for="${esc(inputId)}">${esc(def.label)}</label>
                    <input id="${esc(inputId)}" data-dqc-field="${esc(fieldKey)}" class="form-control form-control-sm border-warning border-2" type="text" ${canRun ? "" : "disabled"}>
                `;
                dynamicFieldsHost.appendChild(wrap);
                const input = wrap.querySelector("input");
                if (input) {
                    input.value = String(item[fieldKey] ?? "");
                    activeFieldInputs.push(input);
                }
            });
            headerFieldsWrap.hidden = false;
            applyFieldsBtn.disabled = !activeFieldInputs.length;
            const rowError = String(item.error_key || "").trim();
            const canMarkAllSame = (
                (activeTable === "legal" && rowError === "legalOutOfRangeQuarterSections")
                || (activeTable === "record_series" && (
                    rowError === "recordSeriesMissingYear"
                    || rowError === "recordSeriesMissingLookup"
                    || rowError === "recordSeriesIncorrectInternalId"
                ))
            );
            markAllSameBtn.hidden = !canMarkAllSame;
            markAllSameBtn.disabled = !canMarkAllSame;
        }
        async function applyFieldUpdates(row, updates) {
            if (!row || !updates || typeof updates !== "object") return;
            const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/apply-fields?table=${encodeURIComponent(activeTable)}`, "POST", {
                updates,
            }, {
                addon_id: app.id,
                addon_type: app.type,
                addon_action: "dqc_apply_fields",
            });
            setBanner(payload.message || "Fields updated.", "success");
            await loadIssues();
            await refreshPendingBadgeForActiveTable();
            queueResizeLayout();
        }
        function issueRowTitle(row) {
            const snapshot = String((row && row.snapshot) || "").trim();
            if (snapshot) return snapshot;
            const fromCol = String((row && row.col01varchar) || "").trim();
            if (fromCol) return fromCol;
            return displayErrorLabel(row && row.error_key, row && row.error_label);
        }
        function renderItems() {
            if (!issues.length) {
                itemsList.innerHTML = `<div class="small text-muted">${hasScanned ? "No issues found for current filters." : "Run scan to load issues."}</div>`;
                setSelection(null);
                return;
            }
            const nextQueuedSelection = () => {
                if (Number.isInteger(selectedIndex) && selectedIndex >= 0 && selectedIndex < issues.length) {
                    return issues[selectedIndex];
                }
                return issues.find((row) => String(row.id) === String(selectedId)) || issues[0];
            };
            const selectedRows = issues.filter((row) => selectedIds.has(String(row.id)));
            if (!selectedRows.length) {
                const current = nextQueuedSelection();
                setSelection(current);
            } else {
                if (!selectedRows.some((row) => String(row.id) === String(selectedId))) {
                    selectedId = selectedRows[0].id;
                }
                const current = issues.find((row) => String(row.id) === String(selectedId)) || selectedRows[0];
                setSelection(current, { preserveMulti: true });
            }
            itemsList.innerHTML = issues.map((row, idx) => `
                <button type="button" class="addons-mii-row ${selectedIds.has(String(row.id)) ? "active" : ""} ${Number(row.has_previous_match || 0) === 1 ? "border border-warning-subtle" : ""}" data-dqc-id="${esc(row.id)}" data-dqc-idx="${esc(idx)}">
                    <div class="d-flex justify-content-between align-items-center gap-2">
                        <span class="fw-semibold">${esc(issueRowTitle(row))}</span>
                        <span class="badge ${Number(row.is_fixed) === 1 ? "text-bg-success" : "text-bg-secondary"}">${Number(row.is_fixed) === 1 ? "fixed" : "pending"}</span>
                    </div>
                    <div class="small text-muted mt-1">${esc(row.__integrated
                        ? `${displayErrorLabel(row.error_key, row.error_label)}${row.file_key ? ` · ${row.file_key}` : ""}`
                        : `${displayErrorLabel(row.error_key, row.error_label)}${row.file_key ? ` · ${row.file_key}` : ""}`
                    )}</div>
                    ${(Number(row.is_fixed) === 1 && String(row.fixed_note || "").trim())
                        ? `<div class="small mt-1"><span class="badge text-bg-dark">${esc(String(row.fixed_note || "").trim())}</span></div>`
                        : ""}
                    ${(Number(row.is_fixed) === 0 && Number(row.has_previous_match || 0) === 1)
                        ? `<div class="small mt-1"><span class="badge text-bg-warning">previous match</span></div>`
                        : ""}
                </button>
            `).join("");
            itemsList.querySelectorAll("[data-dqc-id]").forEach((btn) => {
                btn.addEventListener("click", (event) => {
                    const idx = Number.parseInt(String(btn.getAttribute("data-dqc-idx") || ""), 10);
                    const hit = Number.isInteger(idx) && idx >= 0 && idx < issues.length
                        ? issues[idx]
                        : issues.find((x) => String(x.id) === String(btn.getAttribute("data-dqc-id")));
                    if (!hit) {
                        setSelection(null);
                        renderItems();
                        return;
                    }
                    const rowKey = String(hit.id);
                    const isRange = Boolean(event.shiftKey);
                    if (isRange) {
                        const anchor = Number.isInteger(selectionAnchorIndex) && selectionAnchorIndex >= 0
                            ? selectionAnchorIndex
                            : (Number.isInteger(selectedIndex) && selectedIndex >= 0 ? selectedIndex : idx);
                        const from = Math.max(0, Math.min(anchor, idx));
                        const to = Math.min(issues.length - 1, Math.max(anchor, idx));
                        if (!(event.ctrlKey || event.metaKey)) selectedIds = new Set();
                        for (let i = from; i <= to; i += 1) selectedIds.add(String(issues[i].id));
                        selectedId = hit.id;
                        selectedIndex = idx;
                        const current = selectedItem() || hit;
                        setSelection(current, { preserveMulti: true });
                    } else if (event.ctrlKey || event.metaKey) {
                        if (selectedIds.has(rowKey)) selectedIds.delete(rowKey);
                        else selectedIds.add(rowKey);
                        if (!selectedIds.size) {
                            setSelection(null);
                            renderItems();
                            return;
                        }
                        if (!selectedIds.has(String(selectedId))) selectedId = rowKey;
                        selectionAnchorIndex = idx;
                        const current = selectedItem() || hit;
                        setSelection(current, { preserveMulti: true });
                    } else {
                        setSelection(hit);
                    }
                    renderItems();
                    loadImages().catch((err) => setBanner(err.message, "danger"));
                });
            });
            loadImages().catch((err) => setBanner(err.message, "danger"));
            queueResizeLayout();
        }
        async function loadErrorTypes() {
            const status = mapDqcStatusToBase(statusFilter.value || "pending");
            const extraRows = await loadIntegratedErrorCounts(status, activeTable);
            if (!hasScanned && !extraRows.length) {
                currentErrorRows = [];
                errorFilter.innerHTML = `<option value="">Run scan to detect errors</option>`;
                errorFilter.value = "";
                errorFilter.disabled = true;
                return;
            }
            const useIntegratedOnly = Boolean(activeSecondaryIntegratedErrorKey(activeTable));
            let baseRows = [];
            if (!useIntegratedOnly) {
                const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/error-types?table=${encodeURIComponent(activeTable)}&status=${encodeURIComponent(status)}`, "GET", null, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_error_types",
                });
                baseRows = Array.isArray(payload.items) ? payload.items : [];
            }
            const rows = [...baseRows, ...extraRows].filter((row) => (Number(row && row.issue_count || 0) || 0) > 0);
            currentErrorRows = rows.slice();
            const selected = String(errorFilter.value || "").trim();
            errorFilter.innerHTML = rows.map((row) =>
                `<option value="${esc(row.error_key || "")}">${esc(displayErrorLabel(row.error_key, row.error_label))} (${esc(row.issue_count || 0)})</option>`
            ).join("");
            if (!rows.length) {
                currentErrorRows = [];
                errorFilter.innerHTML = `<option value="">No errors detected</option>`;
                errorFilter.value = "";
                errorFilter.disabled = true;
                return;
            }
            errorFilter.disabled = false;
            const hasSelected = rows.some((row) => String(row.error_key || "") === selected);
            errorFilter.value = hasSelected ? selected : String(rows[0].error_key || "");
        }
        async function refreshPendingBadgeForActiveTable() {
            const selectedErrorKey = String(errorFilter.value || "").trim();
            if (!selectedErrorKey) {
                syncAppPendingBadge(0);
                return;
            }
            const allRows = Array.isArray(currentErrorRows) ? currentErrorRows : [];
            const match = allRows.find((row) => String(row.error_key || "") === selectedErrorKey);
            syncAppPendingBadge(Number(match && match.issue_count ? match.issue_count : 0) || 0);
        }
        async function loadIssues() {
            const errorKey = String(errorFilter.value || "").trim();
            if (!errorKey) {
                issues = [];
                totalCount = 0;
                totalPages = 1;
                renderPager();
                renderItems();
                return;
            }
            const spec = integratedSpecForError(errorKey);
            if (spec) {
                await loadIntegratedIssues(errorKey);
                return;
            }
            if (!hasScanned) {
                issues = [];
                totalCount = 0;
                totalPages = 1;
                renderPager();
                renderItems();
                return;
            }
            const q = new URLSearchParams({ table: activeTable, status: mapDqcStatusToBase(statusFilter.value || "pending") });
            q.set("error_key", errorKey);
            q.set("page", String(currentPage));
            q.set("page_size", String(pageSize));
            const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items?${q.toString()}`, "GET", null, {
                addon_id: app.id,
                addon_type: app.type,
                addon_action: "dqc_items",
            });
            totalCount = Number(payload.total_count || 0) || 0;
            totalPages = Number(payload.total_pages || Math.max(1, Math.ceil(totalCount / pageSize))) || 1;
            if (totalPages < 1) totalPages = 1;
            if (currentPage > totalPages) {
                currentPage = totalPages;
                renderPager();
                return loadIssues();
            }
            const baseRows = Array.isArray(payload.items) ? payload.items : [];
            issues = baseRows.map((row) => {
                const parseOriginalFromSnapshot = (snapshotText, fallbackValue) => {
                    const raw = String(snapshotText || "").trim();
                    const fallback = String(fallbackValue || "").trim();
                    if (!raw) return fallback;
                    const match = raw.match(/(?:^|[;,]\s*)original\s*=\s*([^;]+)/i);
                    if (!match || !match[1]) return fallback;
                    const val = String(match[1] || "").trim();
                    return val || fallback;
                };
                const key = String(row.error_key || "").trim();
                const bridgeType = key === "instTypeMissingLookup"
                    ? "correcting_instrument_types"
                    : (key === "additionMissingLookup" ? "correcting_additions" : "");
                const integratedRowId = Number(row.integrated_row_id || 0);
                if (!bridgeType || !integratedRowId) return row;
                const spec = bridgeType === "correcting_instrument_types"
                    ? integratedSpecForError("__instrument_types__")
                    : integratedSpecForError("__additions__");
                if (!spec) return row;
                const bridgeRow = {
                    ...row,
                    original_instrument_type: parseOriginalFromSnapshot(row.snapshot, String(row.col03varchar || row.col01varchar || "")),
                    original_addition_value: parseOriginalFromSnapshot(row.snapshot, String(row.col05varchar || row.col01varchar || "")),
                    block_value: String(row.col06varchar || ""),
                    lot_value: String(row.col07varchar || ""),
                    new_instrument_type_name: String(row.new_instrument_type_name || ""),
                    new_instrument_type_id: String(row.new_instrument_type_id || ""),
                    new_record_type: String(row.new_record_type || ""),
                    new_addition_name: String(row.new_addition_name || ""),
                    new_addition_id: String(row.new_addition_id || ""),
                    new_addition_description: String(row.new_addition_description || ""),
                    new_is_active: (row.new_is_active === undefined || row.new_is_active === null) ? 1 : Number(row.new_is_active || 0),
                };
                return {
                    ...row,
                    __integrated: {
                        spec,
                        addon_id: app.id,
                        addon_type: app.type,
                        row_id: String(integratedRowId),
                        row: bridgeRow,
                    },
                };
            });
            renderPager();
            renderItems();
        }
        async function loadImages() {
            const row = selectedItem();
            if (!row) {
                if (inlineViewer && typeof inlineViewer.clear === "function") inlineViewer.clear("No image selected.");
                return;
            }
            if (row.__integrated) {
                const spec = row.__integrated.spec;
                const addonId = row.__integrated.addon_id;
                const addonType = row.__integrated.addon_type;
                const rowId = row.__integrated.row_id;
                if (String(spec.type || "") === "indexed_images_missing_files" || spec.hasImages === false) {
                    if (inlineViewer && typeof inlineViewer.clear === "function") inlineViewer.clear("No image preview available for this issue.");
                    return;
                }
                if (String(spec.type || "") === "missed_indexing_images") {
                    const rel = String(((row.__integrated || {}).row || {}).relative_path || "").trim();
                    const src = String(((row.__integrated || {}).row || {}).source_key || "").trim().toLowerCase();
                    if (rel && src && inlineViewer && typeof inlineViewer.setFromStream === "function") {
                        inlineViewer.setFromStream(src, rel.replace(/\\/g, "/"), { alt: rel });
                        bindImageWheelBridge();
                        return;
                    }
                }
                if (String(spec.type || "") === "working_images_not_in_source") {
                    const rel = String(((row.__integrated || {}).row || {}).relative_path || "").trim();
                    const src = String(((row.__integrated || {}).row || {}).source_key || "").trim().toLowerCase();
                    if (rel && src && inlineViewer && typeof inlineViewer.setFromStream === "function") {
                        inlineViewer.setFromStream(src, rel.replace(/\\/g, "/"), { alt: rel });
                        bindImageWheelBridge();
                        return;
                    }
                }
                const imageQ = new URLSearchParams();
                if (String(spec.passStage || "").trim()) imageQ.set("pass_stage", String(spec.passStage).trim());
                const payload = await api(`/api/addons/apps/${encodeURIComponent(addonId)}/${spec.routeBase}/items/${encodeURIComponent(rowId)}/images${imageQ.toString() ? `?${imageQ.toString()}` : ""}`, "GET", null, {
                    addon_id: addonId,
                    addon_type: addonType,
                    addon_action: "dqc_integrated_images",
                });
                const imageItems = Array.isArray(payload.items) ? payload.items : [];
                if (!imageItems.length) {
                    if (inlineViewer && typeof inlineViewer.clear === "function") inlineViewer.clear(payload.message || "No associated images found.");
                    return;
                }
                if (inlineViewer && typeof inlineViewer.setFromStreamList === "function") inlineViewer.setFromStreamList(imageItems, { startIndex: 0 });
                else if (inlineViewer && typeof inlineViewer.setFromStream === "function") inlineViewer.setFromStream(imageItems[0].source_key, imageItems[0].relative_path, { alt: imageItems[0].relative_path || "Image preview" });
                bindImageWheelBridge();
                return;
            }
            const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/images?table=${encodeURIComponent(activeTable)}`, "GET", null, {
                addon_id: app.id,
                addon_type: app.type,
                addon_action: "dqc_images",
            });
            const imageItems = Array.isArray(payload.items) ? payload.items : [];
            if (!imageItems.length) {
                if (inlineViewer && typeof inlineViewer.clear === "function") inlineViewer.clear(payload.message || "No associated images found.");
                return;
            }
            if (inlineViewer && typeof inlineViewer.setFromStreamList === "function") inlineViewer.setFromStreamList(imageItems, { startIndex: 0 });
            else if (inlineViewer && typeof inlineViewer.setFromStream === "function") inlineViewer.setFromStream(imageItems[0].source_key, imageItems[0].relative_path, { alt: imageItems[0].relative_path || "Image preview" });
            bindImageWheelBridge();
        }
        async function runBatchSelectionAction(rows, worker) {
            let successCount = 0;
            let skippedCount = 0;
            const errors = [];
            for (const row of rows) {
                try {
                    const result = await worker(row);
                    if (result && result.skipped) skippedCount += 1;
                    else successCount += 1;
                } catch (err) {
                    errors.push(err && err.message ? err.message : String(err || "Unknown error"));
                }
            }
            return { successCount, skippedCount, errors };
        }
        function integratedCorrectionStatusActionLabel(specType) {
            if (specType === "correcting_instrument_types") return "dqc_integrated_instrument_set_status";
            if (specType === "correcting_additions") return "dqc_integrated_additions_set_status";
            return "dqc_integrated_set_status";
        }
        async function setFixedState(isFixed, note = "") {
            const rows = selectedItems();
            if (!rows.length) return;
            const results = await runBatchSelectionAction(rows, async (row) => {
                if (row.__integrated) {
                    const spec = row.__integrated.spec || {};
                    const specType = String(spec.type || "").trim();
                    if (specType === "fix_legal_type_others" || specType === "missing_grantor_grantee_names") {
                        const targetStatus = !Boolean(isFixed) ? "pending" : (String(note || "").trim().toLowerCase() === "ignored" ? "ignored" : "fixed");
                        const actionLabel = specType === "fix_legal_type_others"
                            ? "dqc_integrated_legal_other_set_status"
                            : "dqc_integrated_missing_names_set_status";
                        await callIntegratedActionForRow(
                            row,
                            "set-status",
                            { status: targetStatus },
                            actionLabel,
                            String(row.__integrated.row_id || "").trim(),
                        );
                        return { skipped: false };
                    }
                    if (specType === "correcting_instrument_types" || specType === "correcting_additions") {
                        const isSecondaryIntegrated = String(spec.passStage || "primary").trim().toLowerCase() === "secondary";
                        if (!isSecondaryIntegrated) {
                            await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/set-fixed?table=${encodeURIComponent(activeTable)}`, "POST", {
                                is_fixed: Boolean(isFixed),
                                note: String(note || ""),
                            }, {
                                addon_id: app.id,
                                addon_type: app.type,
                                addon_action: "dqc_set_fixed",
                            });
                            return { skipped: false };
                        }
                        const action = !Boolean(isFixed)
                            ? "pending"
                            : (String(note || "").trim().toLowerCase() === "ignored" ? "ignored" : "fixed");
                        await callIntegratedActionForRow(
                            row,
                            "set-status",
                            { action },
                            integratedCorrectionStatusActionLabel(specType),
                            String(row.__integrated.row_id || "").trim(),
                        );
                        return { skipped: false };
                    }
                    if (specType === "missed_indexing_images" || specType === "indexed_images_missing_files") {
                        const targetStatus = !Boolean(isFixed)
                            ? "pending"
                            : (String(note || "").trim().toLowerCase() === "ignored"
                                ? "ignored"
                                : (specType === "missed_indexing_images" ? "needs_indexed" : "confirmed_missing"));
                        await callIntegratedActionForRow(
                            row,
                            "status",
                            { status: targetStatus },
                            specType === "missed_indexing_images"
                                ? "dqc_integrated_missed_images_set_status"
                                : "dqc_integrated_indexed_missing_set_status",
                            String(row.__integrated.row_id || "").trim(),
                        );
                        return { skipped: false };
                    }
                    if (specType === "working_images_not_in_source") {
                        const targetStatus = !Boolean(isFixed)
                            ? "pending"
                            : (String(note || "").trim().toLowerCase() === "ignored" ? "ignored" : "confirmed_missing");
                        await callIntegratedActionForRow(
                            row,
                            "status",
                            { status: targetStatus },
                            "dqc_integrated_working_not_source_set_status",
                            String(row.__integrated.row_id || "").trim(),
                        );
                        return { skipped: false };
                    }
                    return { skipped: true };
                }
                await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/set-fixed?table=${encodeURIComponent(activeTable)}`, "POST", {
                    is_fixed: Boolean(isFixed),
                    note: String(note || ""),
                }, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_set_fixed",
                });
                return { skipped: false };
            });
            await loadErrorTypes();
            await loadIssues();
            await refreshPendingBadgeForActiveTable();
            queueResizeLayout();
            if (results.errors.length) {
                setBanner(`Updated ${results.successCount} row(s), skipped ${results.skippedCount}, failed ${results.errors.length}. First error: ${results.errors[0]}`, "danger");
                return;
            }
            if (results.skippedCount) {
                setBanner(`Updated ${results.successCount} row(s). Skipped ${results.skippedCount} unsupported row(s).`, "warning");
                return;
            }
            setBanner(`Updated ${results.successCount} row(s).`, "success");
        }
        async function markSelectedForDelete() {
            const rows = selectedItems();
            if (!rows.length) return;
            const runDelete = async () => {
                const results = await runBatchSelectionAction(rows, async (row) => {
                    if (row.__integrated) {
                        const specType = String(((row.__integrated.spec) || {}).type || "").trim();
                        if (specType === "fix_legal_type_others" || specType === "missing_grantor_grantee_names") {
                            const spec = row.__integrated.spec || {};
                            await callIntegratedActionForRow(
                                row,
                                "set-status",
                                { status: "deleted" },
                                specType === "fix_legal_type_others"
                                    ? "dqc_integrated_legal_other_set_status"
                                    : "dqc_integrated_missing_names_set_status",
                                String(row.__integrated.row_id || "").trim(),
                            );
                            return { skipped: false };
                        }
                        if (specType === "correcting_instrument_types" || specType === "correcting_additions") {
                            const isSecondaryIntegrated = String((((row.__integrated || {}).spec) || {}).passStage || "primary").trim().toLowerCase() === "secondary";
                            if (!isSecondaryIntegrated) {
                                await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/mark-delete?table=${encodeURIComponent(activeTable)}`, "POST", {}, {
                                    addon_id: app.id,
                                    addon_type: app.type,
                                    addon_action: "dqc_mark_delete",
                                });
                                return { skipped: false };
                            }
                            await callIntegratedActionForRow(
                                row,
                                "set-status",
                                { action: "delete" },
                                integratedCorrectionStatusActionLabel(specType),
                                String(row.__integrated.row_id || "").trim(),
                            );
                            return { skipped: false };
                        }
                        return { skipped: true };
                    }
                    await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/mark-delete?table=${encodeURIComponent(activeTable)}`, "POST", {}, {
                        addon_id: app.id,
                        addon_type: app.type,
                        addon_action: "dqc_mark_delete",
                    });
                    return { skipped: false };
                });
                await loadErrorTypes();
                await loadIssues();
                await refreshPendingBadgeForActiveTable();
                queueResizeLayout();
                return results;
            };
            const results = rows.length > 1
                ? await withProcessingPopup(
                    "Marking Records for Delete",
                    "Processing selected records. Please wait until this finishes.",
                    runDelete
                )
                : await runDelete();
            if (results.errors.length) {
                setBanner(`Marked ${results.successCount} row(s), skipped ${results.skippedCount}, failed ${results.errors.length}. First error: ${results.errors[0]}`, "danger");
                return;
            }
            if (results.skippedCount) {
                setBanner(`Marked ${results.successCount} row(s) for delete. Skipped ${results.skippedCount} unsupported row(s).`, "warning");
                return;
            }
            setBanner(`Marked ${results.successCount} row(s) for delete.`, "success");
        }
        async function restoreSelectedDeletion() {
            const rows = selectedItems();
            if (!rows.length) return;
            const results = await runBatchSelectionAction(rows, async (row) => {
                if (row.__integrated) {
                    const specType = String(((row.__integrated.spec) || {}).type || "").trim();
                    if (specType === "fix_legal_type_others" || specType === "missing_grantor_grantee_names") {
                        await callIntegratedActionForRow(
                            row,
                            "set-status",
                            { status: "pending" },
                            specType === "fix_legal_type_others"
                                ? "dqc_integrated_legal_other_set_status"
                                : "dqc_integrated_missing_names_set_status",
                            String(row.__integrated.row_id || "").trim(),
                        );
                        return { skipped: false };
                    }
                    if (specType === "correcting_instrument_types" || specType === "correcting_additions") {
                        const isSecondaryIntegrated = String((((row.__integrated || {}).spec) || {}).passStage || "primary").trim().toLowerCase() === "secondary";
                        if (!isSecondaryIntegrated) {
                            await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/mark-restore?table=${encodeURIComponent(activeTable)}`, "POST", {}, {
                                addon_id: app.id,
                                addon_type: app.type,
                                addon_action: "dqc_mark_restore",
                            });
                            return { skipped: false };
                        }
                        await callIntegratedActionForRow(
                            row,
                            "set-status",
                            { action: "restore_delete" },
                            integratedCorrectionStatusActionLabel(specType),
                            String(row.__integrated.row_id || "").trim(),
                        );
                        return { skipped: false };
                    }
                    return { skipped: true };
                }
                await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/mark-restore?table=${encodeURIComponent(activeTable)}`, "POST", {}, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_mark_restore",
                });
                return { skipped: false };
            });
            await loadErrorTypes();
            await loadIssues();
            await refreshPendingBadgeForActiveTable();
            queueResizeLayout();
            if (results.errors.length) {
                setBanner(`Restored ${results.successCount} row(s), skipped ${results.skippedCount}, failed ${results.errors.length}. First error: ${results.errors[0]}`, "danger");
                return;
            }
            if (results.skippedCount) {
                setBanner(`Restored ${results.successCount} row(s). Skipped ${results.skippedCount} unsupported row(s).`, "warning");
                return;
            }
            setBanner(`Restored ${results.successCount} row(s).`, "success");
        }
        async function markSelectedInstrumentForDelete() {
            const rows = selectedItems();
            if (!rows.length) return;
            const runDelete = async () => {
                const results = await runBatchSelectionAction(rows, async (row) => {
                    if (row.__integrated) {
                        const specType = String(((row.__integrated.spec) || {}).type || "").trim();
                        if (specType === "fix_legal_type_others" || specType === "missing_grantor_grantee_names") {
                            await callIntegratedActionForRow(
                                row,
                                "set-status",
                                { status: "deleted" },
                                specType === "fix_legal_type_others"
                                    ? "dqc_integrated_legal_other_set_status"
                                    : "dqc_integrated_missing_names_set_status",
                                String(row.__integrated.row_id || "").trim(),
                            );
                            return { skipped: false };
                        }
                        if (specType === "correcting_instrument_types" || specType === "correcting_additions") {
                            const isSecondaryIntegrated = String((((row.__integrated || {}).spec) || {}).passStage || "primary").trim().toLowerCase() === "secondary";
                            if (!isSecondaryIntegrated) {
                                await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/mark-delete-instrument?table=${encodeURIComponent(activeTable)}`, "POST", {}, {
                                    addon_id: app.id,
                                    addon_type: app.type,
                                    addon_action: "dqc_mark_delete_instrument",
                                });
                                return { skipped: false };
                            }
                            await callIntegratedActionForRow(
                                row,
                                "set-status",
                                { action: "delete_instrument" },
                                integratedCorrectionStatusActionLabel(specType),
                                String(row.__integrated.row_id || "").trim(),
                            );
                            return { skipped: false };
                        }
                        return { skipped: true };
                    }
                    await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/mark-delete-instrument?table=${encodeURIComponent(activeTable)}`, "POST", {}, {
                        addon_id: app.id,
                        addon_type: app.type,
                        addon_action: "dqc_mark_delete_instrument",
                    });
                    return { skipped: false };
                });
                await loadErrorTypes();
                await loadIssues();
                await refreshPendingBadgeForActiveTable();
                queueResizeLayout();
                return results;
            };
            const results = rows.length > 1
                ? await withProcessingPopup(
                    "Marking Instrument for Delete",
                    "Processing selected records. Please wait until this finishes.",
                    runDelete
                )
                : await runDelete();
            if (results.errors.length) {
                setBanner(`Marked ${results.successCount} instrument row(s), skipped ${results.skippedCount}, failed ${results.errors.length}. First error: ${results.errors[0]}`, "danger");
                return;
            }
            if (results.skippedCount) {
                setBanner(`Marked ${results.successCount} instrument row(s). Skipped ${results.skippedCount} unsupported row(s).`, "warning");
                return;
            }
            setBanner(`Marked ${results.successCount} instrument row(s).`, "success");
        }
        async function restoreSelectedInstrumentDelete() {
            const rows = selectedItems();
            if (!rows.length) return;
            const results = await runBatchSelectionAction(rows, async (row) => {
                if (row.__integrated) {
                    const specType = String(((row.__integrated.spec) || {}).type || "").trim();
                    if (specType === "fix_legal_type_others" || specType === "missing_grantor_grantee_names") {
                        await callIntegratedActionForRow(
                            row,
                            "set-status",
                            { status: "pending" },
                            specType === "fix_legal_type_others"
                                ? "dqc_integrated_legal_other_set_status"
                                : "dqc_integrated_missing_names_set_status",
                            String(row.__integrated.row_id || "").trim(),
                        );
                        return { skipped: false };
                    }
                    if (specType === "correcting_instrument_types" || specType === "correcting_additions") {
                        const isSecondaryIntegrated = String((((row.__integrated || {}).spec) || {}).passStage || "primary").trim().toLowerCase() === "secondary";
                        if (!isSecondaryIntegrated) {
                            await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/mark-restore-instrument?table=${encodeURIComponent(activeTable)}`, "POST", {}, {
                                addon_id: app.id,
                                addon_type: app.type,
                                addon_action: "dqc_mark_restore_instrument",
                            });
                            return { skipped: false };
                        }
                        await callIntegratedActionForRow(
                            row,
                            "set-status",
                            { action: "restore_instrument" },
                            integratedCorrectionStatusActionLabel(specType),
                            String(row.__integrated.row_id || "").trim(),
                        );
                        return { skipped: false };
                    }
                    return { skipped: true };
                }
                await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/mark-restore-instrument?table=${encodeURIComponent(activeTable)}`, "POST", {}, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_mark_restore_instrument",
                });
                return { skipped: false };
            });
            await loadErrorTypes();
            await loadIssues();
            await refreshPendingBadgeForActiveTable();
            queueResizeLayout();
            if (results.errors.length) {
                setBanner(`Restored ${results.successCount} instrument row(s), skipped ${results.skippedCount}, failed ${results.errors.length}. First error: ${results.errors[0]}`, "danger");
                return;
            }
            if (results.skippedCount) {
                setBanner(`Restored ${results.successCount} instrument row(s). Skipped ${results.skippedCount} unsupported row(s).`, "warning");
                return;
            }
            setBanner(`Restored ${results.successCount} instrument row(s).`, "success");
        }
        async function applyHeaderFields() {
            const row = selectedItem();
            if (!row) return;
            if (!activeFieldInputs.length) return;
            const updates = {};
            activeFieldInputs.forEach((input) => {
                const key = String(input.getAttribute("data-dqc-field") || "").trim();
                if (!key) return;
                updates[key] = String(input.value || "").trim();
            });
            await applyFieldUpdates(row, updates);
        }
        async function markAllAsSame() {
            const row = selectedItem();
            if (!row || row.__integrated) return;
            const rowError = String(row.error_key || "").trim();
            const isLegalQuarter = activeTable === "legal" && rowError === "legalOutOfRangeQuarterSections";
            const isRecordSeries = activeTable === "record_series" && (
                rowError === "recordSeriesMissingYear"
                || rowError === "recordSeriesMissingLookup"
                || rowError === "recordSeriesIncorrectInternalId"
            );
            if (!isLegalQuarter && !isRecordSeries) return;
            const quarterInput = activeFieldInputs.find((input) => String(input.getAttribute("data-dqc-field") || "").trim() === "col08varchar");
            const yearInput = activeFieldInputs.find((input) => String(input.getAttribute("data-dqc-field") || "").trim() === "year");
            const rsInternalInput = activeFieldInputs.find((input) => String(input.getAttribute("data-dqc-field") || "").trim() === "record_series_internal_id");
            const quarter = String((quarterInput && quarterInput.value) || row.col08varchar || "").trim();
            const year = String((yearInput && yearInput.value) || row.year || "").trim();
            const recordSeriesInternalId = String((rsInternalInput && rsInternalInput.value) || row.record_series_internal_id || "").trim();
            const payloadBody = isLegalQuarter
                ? { quarter }
                : { year, record_series_internal_id: recordSeriesInternalId };
            await withProcessingPopup(
                "Applying Mark As Same",
                "Processing matching records. Please wait until this finishes.",
                async () => {
                    const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/items/${encodeURIComponent(row.id)}/match-all-same?table=${encodeURIComponent(activeTable)}`, "POST", payloadBody, {
                        addon_id: app.id,
                        addon_type: app.type,
                        addon_action: "dqc_mark_all_same",
                    });
                    setBanner(payload.message || "Marked all matching rows.", "success");
                    await loadErrorTypes();
                    await loadIssues();
                    await refreshPendingBadgeForActiveTable();
                    queueResizeLayout();
                }
            );
        }
        async function runIntegratedScansForDataQuality() {
            return Promise.resolve();
        }
        function buildLogsQueryString() {
            if (!hasFixedTable) return "";
            const q = new URLSearchParams();
            if (activeTable) q.set("table", activeTable);
            if (activeTable === "instrument_types" || activeTable === "additions") {
                const passStage = activeIntegratedPassStage(activeTable);
                if (passStage) q.set("pass_stage", passStage);
            }
            return q.toString();
        }
        async function hydrateScanStateFromLogs() {
            let payload = { logs: [], count: 0, has_scanned: false, counts: {} };
            try {
                const logsQuery = buildLogsQueryString();
                payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/logs${logsQuery ? `?${logsQuery}` : ""}`, "GET", null, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_logs_bootstrap",
                });
            } catch (err) {
                reportDebug(err, {
                    source: "addons_api",
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_logs_bootstrap_recoverable",
                });
            }
            let countsPayload = null;
            try {
                countsPayload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/counts`, "GET", null, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_counts_bootstrap",
                });
            } catch (err) {
                reportDebug(err, {
                    source: "addons_api",
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_counts_bootstrap_recoverable",
                });
            }
            const entries = Array.isArray(payload.logs) ? payload.logs : [];
            const effectiveCounts = countsPayload && countsPayload.counts && typeof countsPayload.counts === "object"
                ? countsPayload.counts
                : (payload.counts && typeof payload.counts === "object" ? payload.counts : null);
            hasScanned = Boolean((countsPayload && countsPayload.has_scanned) || payload.has_scanned)
                || entries.some((entry) => String(entry.event_type || "").trim().toLowerCase() === "scan_completed");
            if (effectiveCounts) {
                setTablePendingCountsFromObject(effectiveCounts);
            }
            return {
                ...payload,
                has_scanned: hasScanned,
                counts: effectiveCounts || {},
            };
        }
        function renderLogsTable(rows) {
            logs = Array.isArray(rows) ? rows.slice() : [];
            if (!logs.length) {
                logsHost.innerHTML = `<div class="small text-muted">No logs found for your current working county scope.</div>`;
                return;
            }
            logsHost.innerHTML = `
                <div class="table-responsive">
                    <table class="table table-sm align-middle addons-logs-table">
                        <thead><tr><th>Time</th><th>User</th><th>Severity</th><th>Event</th><th>Table</th><th>Message</th><th>Details</th></tr></thead>
                        <tbody>
                            ${logs.map((entry) => `
                                <tr>
                                    <td class="text-nowrap">${esc(entry.audit_time || "")}</td>
                                    <td class="text-nowrap">${esc(entry.actor_username || `User #${entry.imported_by_user_id || "-"}`)}</td>
                                    <td><span class="addons-log-badge ${severityBadgeClass(entry.severity)}">${esc(entry.severity || "info")}</span></td>
                                    <td>${esc(entry.event_type || "")}</td>
                                    <td>${esc(entry.table_key || "")}</td>
                                    <td>${esc(entry.message || "")}</td>
                                    <td>${entry.details ? `<button type="button" class="btn btn-outline-secondary btn-sm" data-dqc-log-id="${esc(entry.id || "")}">View</button>` : "-"}</td>
                                </tr>
                            `).join("")}
                        </tbody>
                    </table>
                </div>
            `;
        }
        function resizeLayout() {
            if (!workspace) return;
            const headerCard = document.getElementById("dqcHeaderBar");
            const wsRect = workspace.getBoundingClientRect();
            const headerH = headerCard ? headerCard.getBoundingClientRect().height : 0;
            const rootTarget = Math.max(320, Math.floor(wsRect.height - 16));
            root.style.height = `${rootTarget}px`;
            const mainRect = mainRow.getBoundingClientRect();
            const actionRect = actionBar.getBoundingClientRect();
            const bottomPad = 6;
            const computedMain = Math.floor(actionRect.top - mainRect.top - bottomPad);
            const fallbackMain = Math.floor(rootTarget - headerH - actionRect.height - 16);
            const mainTarget = Math.max(220, Number.isFinite(computedMain) && computedMain > 0 ? computedMain : fallbackMain);
            mainRow.style.height = `${mainTarget}px`;
            mainRow.style.minHeight = `${mainTarget}px`;
            mainRow.style.overflowY = "hidden";
            mainRow.style.overflowX = "hidden";

            const sizePaneBody = (paneEl, bodyEl) => {
                const paneRect = paneEl.getBoundingClientRect();
                const children = Array.from(paneEl.children);
                let used = 0;
                children.forEach((child) => {
                    if (child === bodyEl) return;
                    const style = window.getComputedStyle(child);
                    if (style.position === "absolute" || style.position === "fixed") return;
                    const rect = child.getBoundingClientRect();
                    used += rect.height
                        + (parseFloat(style.marginTop) || 0)
                        + (parseFloat(style.marginBottom) || 0);
                });
                const available = Math.max(0, Math.floor(paneRect.height - used - 8));
                bodyEl.style.height = `${available}px`;
            };

            queueCol.style.height = `${mainTarget}px`;
            queueCol.style.minHeight = `${mainTarget}px`;
            queueCol.style.maxHeight = `${mainTarget}px`;
            queueCol.style.overflow = "hidden";
            queueCol.style.position = "relative";
            queueCol.style.top = "auto";
            queueCol.style.alignSelf = "stretch";
            queueCol.style.zIndex = "auto";
            queuePane.style.position = "relative";
            queuePane.style.left = "auto";
            queuePane.style.top = "auto";
            queuePane.style.width = "100%";
            queuePane.style.height = "100%";
            queuePane.style.minHeight = "100%";
            queuePane.style.maxHeight = "100%";
            queuePane.style.zIndex = "auto";
            sizePaneBody(queuePane, queueBody);

            queueBody.style.overflowY = "scroll";
            queueBody.style.overflowX = "hidden";
            imageMainCol.style.height = `${mainTarget}px`;
            imageMainCol.style.minHeight = `${mainTarget}px`;
            imageMainCol.style.maxHeight = `${mainTarget}px`;
            imageMainCol.style.overflowY = "hidden";
            imageMainCol.style.overflowX = "hidden";
            previewWrap.style.height = "100%";
            previewWrap.style.maxHeight = "100%";
            previewWrap.style.overflow = "hidden";
            if (inlineViewer && typeof inlineViewer.refreshLayout === "function") inlineViewer.refreshLayout();
        }
        function queueResizeLayout() {
            window.requestAnimationFrame(() => {
                resizeLayout();
                window.setTimeout(resizeLayout, 80);
                window.setTimeout(resizeLayout, 180);
            });
        }
        function bindImageWheelBridge() {
            const viewport = previewWrap.querySelector(".gsi-image-viewport");
            if (!viewport) return;
            if (viewport.dataset.dqcWheelBridgeBound === "1") return;
            viewport.dataset.dqcWheelBridgeBound = "1";
            viewport.addEventListener("wheel", (event) => {
                if (event.ctrlKey) return;
                const maxTop = Math.max(0, viewport.scrollHeight - viewport.clientHeight);
                const atTop = viewport.scrollTop <= 0;
                const atBottom = viewport.scrollTop >= maxTop - 1;
                if ((event.deltaY < 0 && atTop) || (event.deltaY > 0 && atBottom)) {
                    return;
                }
            }, { passive: false });
        }
        function toggleActionPanel(panel, toggleBtn) {
            const willShow = panel.classList.contains("d-none");
            if (willShow) {
                scanGroupPanel.classList.add("d-none");
                reviewGroupPanel.classList.add("d-none");
                scanGroupToggle.classList.remove("active");
                reviewGroupToggle.classList.remove("active");
            }
            panel.classList.toggle("d-none", !willShow);
            toggleBtn.classList.toggle("active", willShow);
        }

        tableSelector.addEventListener("change", async () => {
            if (hasFixedTable) return;
            activeTable = String(tableSelector.value || "header").trim() || "header";
            currentPage = 1;
            setTableState();
            hideEditOverlay();
            try {
                await loadErrorTypes();
                await loadIssues();
                await refreshPendingBadgeForActiveTable();
            } catch (err) {
                setBanner(err.message, "danger");
            }
        });
        statusFilter.addEventListener("change", async () => {
            currentPage = 1;
            hideEditOverlay();
            try {
                await loadErrorTypes();
                await loadIssues();
                await refreshPendingBadgeForActiveTable();
            } catch (err) {
                setBanner(err.message, "danger");
            }
        });
        passFilter.addEventListener("change", async () => {
            const nextStage = String(passFilter.value || "primary").trim().toLowerCase() === "secondary"
                ? "secondary"
                : "primary";
            if (activeTable === "instrument_types") instrumentTypePassStage = nextStage;
            else if (activeTable === "additions") additionsPassStage = nextStage;
            currentPage = 1;
            hideEditOverlay();
            try {
                await loadErrorTypes();
                await loadIssues();
                await refreshPendingBadgeForActiveTable();
            } catch (err) {
                setBanner(err.message, "danger");
            }
        });
        errorFilter.addEventListener("change", () => {
            currentPage = 1;
            hideEditOverlay();
            loadIssues()
                .then(refreshPendingBadgeForActiveTable)
                .catch((err) => setBanner(err.message, "danger"));
        });
        scanGroupToggle.addEventListener("click", () => toggleActionPanel(scanGroupPanel, scanGroupToggle));
        reviewGroupToggle.addEventListener("click", () => toggleActionPanel(reviewGroupPanel, reviewGroupToggle));
        scanBtn.addEventListener("click", async () => {
            scanBtn.disabled = true;
            try {
                const reuseJobScopeCorrections = await popupConfirm(
                    "Yes will reuse corrections you already made for this same job scope on the core DQ tables. No runs a fresh scan for the current job scope. Additions and instrument types are handled separately in their own correction flows.",
                    {
                        title: "Reuse Job Scope Corrections?",
                        confirmText: "Yes, Reuse",
                        cancelText: "No, Fresh Scan",
                    }
                );
                popupProgressStart(
                    "Scanning Records",
                    reuseJobScopeCorrections
                        ? "Scanning records and applying saved corrections for this job scope..."
                        : "Scanning split tables for quality issues..."
                );
                const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/scan`, "POST", {
                    apply_scope_history: Boolean(reuseJobScopeCorrections),
                }, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_scan",
                });
                await runIntegratedScansForDataQuality();
                hasScanned = true;
                currentPage = 1;
                if (payload.counts && typeof payload.counts === "object") {
                    setTablePendingCountsFromObject(payload.counts);
                }
                popupProgressStop();
                setBanner(payload.message || "Scan completed.", "success");
                await loadErrorTypes();
                await loadIssues();
                await refreshPendingBadgeForActiveTable();
            } catch (err) {
                setBanner(err.message, "danger");
            } finally {
                popupProgressStop();
                scanBtn.disabled = false;
            }
        });
        markFixedBtn.addEventListener("click", () => setFixedState(true).catch((err) => setBanner(err.message, "danger")));
        markDeleteBtn.addEventListener("click", () => markSelectedForDelete().catch((err) => setBanner(err.message, "danger")));
        markInstrumentDeleteBtn.addEventListener("click", () => markSelectedInstrumentForDelete().catch((err) => setBanner(err.message, "danger")));
        restoreInstrumentBtn.addEventListener("click", () => restoreSelectedInstrumentDelete().catch((err) => setBanner(err.message, "danger")));
        restoreDeleteBtn.addEventListener("click", () => restoreSelectedDeletion().catch((err) => setBanner(err.message, "danger")));
        ignoreBtn.addEventListener("click", () => setFixedState(true, "ignored").catch((err) => setBanner(err.message, "danger")));
        markPendingBtn.addEventListener("click", () => setFixedState(false).catch((err) => setBanner(err.message, "danger")));
        undoLastBtn.addEventListener("click", () => undoLastChange().catch((err) => setBanner(err.message, "danger")));
        editRecordBtn.addEventListener("click", () => {
            showEditOverlay();
            queueResizeLayout();
        });
        editCloseBtn.addEventListener("click", () => {
            hideEditOverlay();
            queueResizeLayout();
        });
        applyFieldsBtn.addEventListener("click", () => applyHeaderFields().catch((err) => setBanner(err.message, "danger")));
        markAllSameBtn.addEventListener("click", () => markAllAsSame().catch((err) => setBanner(err.message, "danger")));
        needsInsertBtn.addEventListener("click", () => setFixedState(true, "needs_inserted").catch((err) => setBanner(err.message, "danger")));
        prevPageBtn.addEventListener("click", () => {
            const usableTotalPages = Math.max(1, totalPages);
            if (usableTotalPages <= 1) return;
            currentPage = currentPage <= 1 ? usableTotalPages : currentPage - 1;
            loadIssues().catch((err) => setBanner(err.message, "danger"));
        });
        nextPageBtn.addEventListener("click", () => {
            const usableTotalPages = Math.max(1, totalPages);
            if (usableTotalPages <= 1) return;
            currentPage = currentPage >= usableTotalPages ? 1 : currentPage + 1;
            loadIssues().catch((err) => setBanner(err.message, "danger"));
        });
        viewLogsBtn.addEventListener("click", async () => {
            viewLogsBtn.disabled = true;
            try {
                const logsQuery = buildLogsQueryString();
                const payload = await api(`/api/addons/apps/${encodeURIComponent(app.id)}/data-quality-corrections/logs${logsQuery ? `?${logsQuery}` : ""}`, "GET", null, {
                    addon_id: app.id,
                    addon_type: app.type,
                    addon_action: "dqc_logs",
                });
                renderLogsTable(Array.isArray(payload.logs) ? payload.logs : []);
                logsWrap.hidden = false;
                queueResizeLayout();
            } catch (err) {
                setBanner(err.message, "danger");
            } finally {
                viewLogsBtn.disabled = false;
            }
        });
        logsHideBtn.addEventListener("click", () => {
            logsWrap.hidden = true;
            queueResizeLayout();
        });
        logsHost.addEventListener("click", async (event) => {
            const btn = event.target.closest("[data-dqc-log-id]");
            if (!btn) return;
            const entry = logs.find((x) => String(x.id) === String(btn.getAttribute("data-dqc-log-id")));
            if (typeof showAuditLogDetails === "function") {
                await showAuditLogDetails(entry);
                return;
            }
            const detailsText = String((entry && (entry.details_display || entry.details || entry.details_raw)) || "").trim();
            if (!detailsText) return;
            await popupAlert(detailsText, {
                title: `${entry.event_type || "Log Details"} (${entry.severity || "info"})`,
                copyText: detailsText,
                copyLabel: "Copy Details",
            });
        });

        const controller = new AbortController();
        const signal = controller.signal;
        window.addEventListener("resize", resizeLayout, { signal });
        document.addEventListener("layout:changed", () => window.setTimeout(resizeLayout, 120), { signal });
        document.addEventListener("module:overlay-opened", () => window.setTimeout(resizeLayout, 120), { signal });
        workspaceTeardown = () => controller.abort();
        if (typeof setWorkspaceTeardown === "function") setWorkspaceTeardown(workspaceTeardown);

        setTableState();
        resizeLayout();
        queueResizeLayout();
        bindImageWheelBridge();
        setAwaitingScanState();
        syncAppPendingBadge(0);
        hydrateScanStateFromLogs()
            .then(async (payload) => {
                const bootstrapCounts = payload && payload.counts && typeof payload.counts === "object"
                    ? payload.counts
                    : null;
                const bootstrapTotal = bootstrapCounts
                    ? Object.values(bootstrapCounts).reduce((sum, value) => sum + (Number(value || 0) || 0), 0)
                    : 0;
                if (hasScanned && (!bootstrapCounts || bootstrapTotal <= 0)) {
                    await refreshTableSelectorCounts();
                }
                await loadErrorTypes();
                await loadIssues();
                await refreshPendingBadgeForActiveTable();
            })
            .catch((err) => setBanner(err.message, "danger"));
    };
})();
