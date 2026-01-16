-- HTMX Template Seeds
-- Description: Sample HTMX templates for purchase orders
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- PURCHASE ORDER LIST TEMPLATE
-- =============================================================================

INSERT INTO htmx_templates (
    entity_type_id,
    view_type,
    template_name,
    base_template,
    version,
    is_active
) VALUES (
    '10000000-0000-0000-0000-000000000001'::UUID,  -- purchase_order entity
    'list',
    'Purchase Order List View',
    '<div class="entity-list" data-entity="purchase_order">
    <!-- Header -->
    <div class="list-header">
        <h2>{{entity_display_name}}</h2>
        <div class="list-actions">
            {{#if user_can_create}}
            <button class="btn btn-primary"
                    hx-get="/ui/purchase_order/form/create"
                    hx-target="#modal"
                    hx-swap="innerHTML">
                <i class="fa fa-plus"></i> Create Purchase Order
            </button>
            {{/if}}
        </div>
    </div>

    <!-- Filters -->
    <div class="list-filters">
        <form hx-get="/ui/purchase_order/list"
              hx-target="#po-list-table"
              hx-trigger="change, submit"
              hx-swap="innerHTML">

            <div class="filter-group">
                <label>Status</label>
                <select name="status" multiple>
                    <option value="draft">Draft</option>
                    <option value="submitted">Submitted</option>
                    <option value="approved">Approved</option>
                    <option value="partially_received">Partially Received</option>
                    <option value="fully_received">Fully Received</option>
                </select>
            </div>

            <div class="filter-group">
                <label>Date From</label>
                <input type="date" name="po_date_gte" placeholder="From date">
            </div>

            <div class="filter-group">
                <label>Date To</label>
                <input type="date" name="po_date_lte" placeholder="To date">
            </div>

            <div class="filter-group">
                <label>Supplier</label>
                <input type="text" name="supplier_name_like" placeholder="Search supplier...">
            </div>

            <button type="submit" class="btn btn-secondary">
                <i class="fa fa-filter"></i> Apply Filters
            </button>
            <button type="reset" class="btn btn-text">Clear</button>
        </form>
    </div>

    <!-- Table -->
    <div id="po-list-table">
        <table class="data-table">
            <thead>
                <tr>
                    <th data-field="po_number" class="sortable"
                        hx-get="/ui/purchase_order/list?sort=po_number"
                        hx-target="#po-list-table">
                        PO Number <i class="fa fa-sort"></i>
                    </th>
                    <th data-field="supplier_name" class="sortable">
                        Supplier <i class="fa fa-sort"></i>
                    </th>
                    <th data-field="po_date" class="sortable">
                        PO Date <i class="fa fa-sort"></i>
                    </th>
                    <th data-field="expected_delivery_date">
                        Expected Delivery
                    </th>
                    <th data-field="total_amount" class="text-right sortable">
                        Total Amount <i class="fa fa-sort"></i>
                    </th>
                    <th data-field="currency">Currency</th>
                    <th data-field="status">Status</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {{#records}}
                <tr>
                    <td>{{po_number}}</td>
                    <td>{{supplier.supplier_name}}</td>
                    <td>{{po_date}}</td>
                    <td>{{expected_delivery_date}}</td>
                    <td class="text-right">{{total_amount}}</td>
                    <td>{{currency}}</td>
                    <td>
                        <span class="badge badge-{{status}}">{{status}}</span>
                    </td>
                    <td class="actions">
                        <button class="btn btn-sm btn-text"
                                hx-get="/ui/purchase_order/form/view?id={{po_id}}"
                                hx-target="#modal"
                                title="View">
                            <i class="fa fa-eye"></i>
                        </button>
                        {{#if ../user_can_edit}}
                        <button class="btn btn-sm btn-text"
                                hx-get="/ui/purchase_order/form/edit?id={{po_id}}"
                                hx-target="#modal"
                                title="Edit">
                            <i class="fa fa-edit"></i>
                        </button>
                        {{/if}}
                        {{#if ../user_can_delete}}
                        <button class="btn btn-sm btn-text btn-danger"
                                hx-delete="/api/purchase_order/{{po_id}}"
                                hx-confirm="Delete this purchase order?"
                                hx-target="closest tr"
                                hx-swap="outerHTML swap:1s"
                                title="Delete">
                            <i class="fa fa-trash"></i>
                        </button>
                        {{/if}}
                    </td>
                </tr>
                {{/records}}
            </tbody>
        </table>

        <!-- Pagination -->
        <div class="pagination">
            <div class="pagination-info">
                Showing {{page_start}} to {{page_end}} of {{total_count}} records
            </div>
            <div class="pagination-controls">
                {{#if has_prev}}
                <button hx-get="/ui/purchase_order/list?page={{prev_page}}"
                        hx-target="#po-list-table"
                        class="btn btn-sm">
                    <i class="fa fa-chevron-left"></i> Previous
                </button>
                {{/if}}

                <span class="page-info">Page {{current_page}} of {{total_pages}}</span>

                {{#if has_next}}
                <button hx-get="/ui/purchase_order/list?page={{next_page}}"
                        hx-target="#po-list-table"
                        class="btn btn-sm">
                    Next <i class="fa fa-chevron-right"></i>
                </button>
                {{/if}}
            </div>
        </div>
    </div>
</div>',
    1,
    TRUE
);

-- =============================================================================
-- PURCHASE ORDER CREATE FORM TEMPLATE
-- =============================================================================

INSERT INTO htmx_templates (
    entity_type_id,
    view_type,
    template_name,
    base_template,
    version,
    is_active
) VALUES (
    '10000000-0000-0000-0000-000000000001'::UUID,
    'form_create',
    'Purchase Order Create Form',
    '<div class="modal-content">
    <div class="modal-header">
        <h3>Create Purchase Order</h3>
        <button class="close-modal" onclick="this.closest(''.modal'').remove()">×</button>
    </div>

    <form hx-post="/api/purchase_order"
          hx-target="#modal"
          hx-swap="outerHTML"
          class="entity-form">

        <div class="modal-body">
            <!-- PO Number (auto-generated) -->
            <div class="form-field">
                <label>PO Number</label>
                <input type="text" name="po_number" value="{{po_number}}" disabled>
                <small class="help-text">Auto-generated on save</small>
            </div>

            <!-- Supplier (Required) -->
            <div class="form-field required">
                <label>Supplier *</label>
                <select name="supplier_id" required
                        hx-get="/api/lookup/suppliers"
                        hx-trigger="focus once"
                        hx-swap="innerHTML">
                    <option value="">Select supplier...</option>
                    {{#suppliers}}
                    <option value="{{supplier_id}}">{{supplier_name}} ({{supplier_code}})</option>
                    {{/suppliers}}
                </select>
                <small class="help-text">Select the vendor for this purchase order</small>
            </div>

            <!-- PO Date -->
            <div class="form-field required">
                <label>PO Date *</label>
                <input type="date" name="po_date" value="{{po_date}}" required>
            </div>

            <!-- Expected Delivery Date -->
            <div class="form-field">
                <label>Expected Delivery Date</label>
                <input type="date" name="expected_delivery_date" value="{{expected_delivery_date}}">
            </div>

            <!-- Currency -->
            <div class="form-field required">
                <label>Currency *</label>
                <select name="currency" required>
                    <option value="USD" selected>USD</option>
                    <option value="EUR">EUR</option>
                    <option value="GBP">GBP</option>
                </select>
            </div>

            <!-- Notes -->
            <div class="form-field">
                <label>Notes</label>
                <textarea name="notes" rows="3">{{notes}}</textarea>
                <small class="help-text">Additional information or special instructions</small>
            </div>

            <!-- Line Items Section -->
            <div class="form-section">
                <h4>Line Items</h4>
                <div id="line-items">
                    <table class="line-items-table">
                        <thead>
                            <tr>
                                <th>Line #</th>
                                <th>Item Code</th>
                                <th>Description</th>
                                <th>Quantity</th>
                                <th>UOM</th>
                                <th>Unit Price</th>
                                <th>Line Total</th>
                                <th></th>
                            </tr>
                        </thead>
                        <tbody id="lines-container">
                            <!-- Lines will be added here -->
                        </tbody>
                    </table>

                    <button type="button" class="btn btn-secondary"
                            onclick="addLineItem()">
                        <i class="fa fa-plus"></i> Add Line Item
                    </button>
                </div>
            </div>

            <!-- Total Amount (Calculated) -->
            <div class="form-field">
                <label>Total Amount</label>
                <input type="text" name="total_amount" value="{{total_amount}}" readonly
                       class="calculated-field">
                <small class="help-text">Automatically calculated from line items</small>
            </div>
        </div>

        <div class="modal-footer">
            <button type="button" class="btn btn-text"
                    onclick="this.closest(''.modal'').remove()">
                Cancel
            </button>
            <button type="submit" class="btn btn-primary">
                <i class="fa fa-save"></i> Create Purchase Order
            </button>
        </div>
    </form>
</div>

<script>
function addLineItem() {
    const container = document.getElementById(''lines-container'');
    const lineNumber = container.children.length + 1;
    const row = document.createElement(''tr'');
    row.innerHTML = `
        <td>${lineNumber}</td>
        <td><input type="text" name="lines[${lineNumber}][item_code]" required></td>
        <td><input type="text" name="lines[${lineNumber}][item_description]" required></td>
        <td><input type="number" name="lines[${lineNumber}][quantity_ordered]" step="0.01" required onchange="calculateLineTotal(${lineNumber})"></td>
        <td><input type="text" name="lines[${lineNumber}][uom]" value="EA" required></td>
        <td><input type="number" name="lines[${lineNumber}][unit_price]" step="0.01" required onchange="calculateLineTotal(${lineNumber})"></td>
        <td><input type="number" name="lines[${lineNumber}][line_total]" step="0.01" readonly class="calculated-field"></td>
        <td><button type="button" class="btn btn-sm btn-text btn-danger" onclick="this.closest(''tr'').remove(); calculateTotal();">×</button></td>
    `;
    container.appendChild(row);
}

function calculateLineTotal(lineNumber) {
    const qty = document.querySelector(`input[name="lines[${lineNumber}][quantity_ordered]"]`).value;
    const price = document.querySelector(`input[name="lines[${lineNumber}][unit_price]"]`).value;
    const total = (parseFloat(qty) || 0) * (parseFloat(price) || 0);
    document.querySelector(`input[name="lines[${lineNumber}][line_total]"]`).value = total.toFixed(2);
    calculateTotal();
}

function calculateTotal() {
    let total = 0;
    document.querySelectorAll(''input[name$="[line_total]"]'').forEach(input => {
        total += parseFloat(input.value) || 0;
    });
    document.querySelector(''input[name="total_amount"]'').value = total.toFixed(2);
}

// Add first line item on load
addLineItem();
</script>',
    1,
    TRUE
);

-- =============================================================================
-- PURCHASE ORDER VIEW FORM TEMPLATE
-- =============================================================================

INSERT INTO htmx_templates (
    entity_type_id,
    view_type,
    template_name,
    base_template,
    version,
    is_active
) VALUES (
    '10000000-0000-0000-0000-000000000001'::UUID,
    'form_view',
    'Purchase Order View Form',
    '<div class="modal-content">
    <div class="modal-header">
        <h3>Purchase Order: {{po_number}}</h3>
        <button class="close-modal" onclick="this.closest(''.modal'').remove()">×</button>
    </div>

    <div class="modal-body">
        <div class="form-view">
            <!-- Status Badge -->
            <div class="status-section">
                <span class="badge badge-lg badge-{{status}}">{{status}}</span>
            </div>

            <!-- Header Information -->
            <div class="form-section">
                <h4>Header Information</h4>
                <div class="detail-grid">
                    <div class="detail-item">
                        <label>PO Number</label>
                        <div class="value">{{po_number}}</div>
                    </div>
                    <div class="detail-item">
                        <label>Supplier</label>
                        <div class="value">{{supplier.supplier_name}}</div>
                    </div>
                    <div class="detail-item">
                        <label>PO Date</label>
                        <div class="value">{{po_date}}</div>
                    </div>
                    <div class="detail-item">
                        <label>Expected Delivery</label>
                        <div class="value">{{expected_delivery_date}}</div>
                    </div>
                    <div class="detail-item">
                        <label>Currency</label>
                        <div class="value">{{currency}}</div>
                    </div>
                    <div class="detail-item">
                        <label>Total Amount</label>
                        <div class="value">{{currency}} {{total_amount}}</div>
                    </div>
                </div>
            </div>

            <!-- Line Items -->
            <div class="form-section">
                <h4>Line Items</h4>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Line #</th>
                            <th>Item Code</th>
                            <th>Description</th>
                            <th>Qty Ordered</th>
                            <th>Qty Received</th>
                            <th>Qty Invoiced</th>
                            <th>UOM</th>
                            <th>Unit Price</th>
                            <th>Line Total</th>
                        </tr>
                    </thead>
                    <tbody>
                        {{#lines}}
                        <tr>
                            <td>{{line_number}}</td>
                            <td>{{item_code}}</td>
                            <td>{{item_description}}</td>
                            <td>{{quantity_ordered}}</td>
                            <td>{{quantity_received}}</td>
                            <td>{{quantity_invoiced}}</td>
                            <td>{{uom}}</td>
                            <td>{{unit_price}}</td>
                            <td>{{line_total}}</td>
                        </tr>
                        {{/lines}}
                    </tbody>
                </table>
            </div>

            <!-- Notes -->
            {{#if notes}}
            <div class="form-section">
                <h4>Notes</h4>
                <div class="notes-content">{{notes}}</div>
            </div>
            {{/if}}

            <!-- Audit Information -->
            <div class="form-section">
                <h4>Audit Information</h4>
                <div class="detail-grid">
                    <div class="detail-item">
                        <label>Created By</label>
                        <div class="value">{{created_by_name}}</div>
                    </div>
                    <div class="detail-item">
                        <label>Created At</label>
                        <div class="value">{{created_at}}</div>
                    </div>
                    {{#if approved_by}}
                    <div class="detail-item">
                        <label>Approved By</label>
                        <div class="value">{{approved_by_name}}</div>
                    </div>
                    <div class="detail-item">
                        <label>Approved At</label>
                        <div class="value">{{approved_at}}</div>
                    </div>
                    {{/if}}
                </div>
            </div>
        </div>
    </div>

    <div class="modal-footer">
        <button type="button" class="btn btn-text"
                onclick="this.closest(''.modal'').remove()">
            Close
        </button>
        {{#if user_can_edit}}
        <button type="button" class="btn btn-primary"
                hx-get="/ui/purchase_order/form/edit?id={{po_id}}"
                hx-target=".modal-content"
                hx-swap="outerHTML">
            <i class="fa fa-edit"></i> Edit
        </button>
        {{/if}}
        {{#if user_can_submit}}
        <button type="button" class="btn btn-success"
                hx-post="/api/purchase_order/{{po_id}}/submit"
                hx-confirm="Submit this purchase order for approval?"
                hx-target=".modal-content"
                hx-swap="outerHTML">
            <i class="fa fa-paper-plane"></i> Submit
        </button>
        {{/if}}
        {{#if user_can_approve}}
        <button type="button" class="btn btn-success"
                hx-post="/api/purchase_order/{{po_id}}/approve"
                hx-confirm="Approve this purchase order?"
                hx-target=".modal-content"
                hx-swap="outerHTML">
            <i class="fa fa-check"></i> Approve
        </button>
        {{/if}}
    </div>
</div>',
    1,
    TRUE
);

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'HTMX templates seeded successfully';
    RAISE NOTICE 'Created 3 templates for purchase_order entity:';
    RAISE NOTICE '  - list: Purchase Order List View';
    RAISE NOTICE '  - form_create: Purchase Order Create Form';
    RAISE NOTICE '  - form_view: Purchase Order View Form';
END $$;
