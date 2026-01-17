-- Extended HTMX Templates
-- Description: Additional templates for all entity types
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- PURCHASE ORDER EDIT FORM TEMPLATE
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
    'form_edit',
    'Purchase Order Edit Form',
    '<div class="modal-content">
    <div class="modal-header">
        <h3>Edit Purchase Order: {{po_number}}</h3>
        <button class="close-modal" onclick="this.closest(''.modal'').remove()">×</button>
    </div>

    <form hx-put="/api/purchase_order/{{po_id}}"
          hx-target="#modal"
          hx-swap="outerHTML"
          class="entity-form">

        <div class="modal-body">
            <!-- Status Badge -->
            <div class="status-section">
                <span class="badge badge-lg badge-{{status}}">{{status}}</span>
            </div>

            <!-- PO Number (Read-only) -->
            <div class="form-field">
                <label>PO Number</label>
                <input type="text" value="{{po_number}}" disabled class="form-control">
            </div>

            <!-- Supplier -->
            {{#if supplier_id_editable}}
            <div class="form-field required">
                <label>Supplier *</label>
                <select name="supplier_id" required class="form-select">
                    <option value="">Select supplier...</option>
                    {{#supplier_id_options}}
                    <option value="{{id}}"{{#if selected}} selected{{/if}}>{{label}}</option>
                    {{/supplier_id_options}}
                </select>
            </div>
            {{/if}}
            {{#if supplier_id_visible}}{{#if not supplier_id_editable}}
            <div class="form-field">
                <label>Supplier</label>
                <input type="text" value="{{supplier.supplier_name}}" disabled class="form-control">
            </div>
            {{/if}}{{/if}}

            <!-- PO Date -->
            <div class="form-field required">
                <label>PO Date *</label>
                <input type="date" name="po_date" value="{{po_date}}"
                       {{#if not po_date_editable}}disabled{{/if}} required class="form-control">
            </div>

            <!-- Expected Delivery Date -->
            <div class="form-field">
                <label>Expected Delivery Date</label>
                <input type="date" name="expected_delivery_date" value="{{expected_delivery_date}}"
                       {{#if not expected_delivery_date_editable}}disabled{{/if}} class="form-control">
            </div>

            <!-- Currency -->
            <div class="form-field required">
                <label>Currency *</label>
                <select name="currency" {{#if not currency_editable}}disabled{{/if}} class="form-select">
                    <option value="USD"{{#if currency == ''USD''}} selected{{/if}}>USD</option>
                    <option value="EUR"{{#if currency == ''EUR''}} selected{{/if}}>EUR</option>
                    <option value="GBP"{{#if currency == ''GBP''}} selected{{/if}}>GBP</option>
                </select>
            </div>

            <!-- Notes -->
            <div class="form-field">
                <label>Notes</label>
                <textarea name="notes" rows="3"
                          {{#if not notes_editable}}disabled{{/if}} class="form-control">{{notes}}</textarea>
            </div>

            <!-- Line Items Section -->
            <div class="form-section">
                <h4>Line Items</h4>
                <table class="data-table" id="line-items-table">
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
                        {{#lines}}
                        <tr data-line-id="{{line_id}}">
                            <td>{{line_number}}</td>
                            <td><input type="text" name="lines[{{line_number}}][item_code]" value="{{item_code}}" class="form-control"></td>
                            <td><input type="text" name="lines[{{line_number}}][item_description]" value="{{item_description}}" class="form-control"></td>
                            <td><input type="number" name="lines[{{line_number}}][quantity_ordered]" value="{{quantity_ordered}}" step="0.01" class="form-control" onchange="calculateLineTotal(this)"></td>
                            <td><input type="text" name="lines[{{line_number}}][uom]" value="{{uom}}" class="form-control"></td>
                            <td><input type="number" name="lines[{{line_number}}][unit_price]" value="{{unit_price}}" step="0.01" class="form-control" onchange="calculateLineTotal(this)"></td>
                            <td><input type="number" name="lines[{{line_number}}][line_total]" value="{{line_total}}" step="0.01" readonly class="form-control calculated"></td>
                            <td><button type="button" class="btn btn-sm btn-danger" onclick="removeLine(this)">×</button></td>
                        </tr>
                        {{/lines}}
                    </tbody>
                </table>
                <button type="button" class="btn btn-secondary" onclick="addLine()">
                    <i class="fa fa-plus"></i> Add Line
                </button>
            </div>

            <!-- Total Amount -->
            <div class="form-field">
                <label>Total Amount</label>
                <input type="text" name="total_amount" value="{{total_amount}}" readonly class="form-control calculated">
            </div>
        </div>

        <div class="modal-footer">
            <button type="button" class="btn btn-text" onclick="this.closest(''.modal'').remove()">
                Cancel
            </button>
            <button type="submit" class="btn btn-primary">
                <i class="fa fa-save"></i> Save Changes
            </button>
        </div>
    </form>
</div>',
    1,
    TRUE
) ON CONFLICT DO NOTHING;

-- =============================================================================
-- SUPPLIER LIST TEMPLATE
-- =============================================================================

INSERT INTO htmx_templates (
    entity_type_id,
    view_type,
    template_name,
    base_template,
    version,
    is_active
) VALUES (
    '10000000-0000-0000-0000-000000000002'::UUID,
    'list',
    'Supplier List View',
    '<div class="entity-list" data-entity="supplier">
    <div class="list-header">
        <h2>{{entity_display_name}}</h2>
        <div class="list-actions">
            {{#if user_can_create}}
            <button class="btn btn-primary"
                    hx-get="/ui/supplier/form/create"
                    hx-target="#modal">
                <i class="fa fa-plus"></i> Add Supplier
            </button>
            {{/if}}
        </div>
    </div>

    <div class="list-filters">
        <form hx-get="/ui/supplier/list"
              hx-target="#supplier-list-table"
              hx-trigger="change, submit">
            <div class="filter-group">
                <input type="text" name="supplier_name_like" placeholder="Search supplier name...">
            </div>
            <div class="filter-group">
                <select name="is_active">
                    <option value="">All Status</option>
                    <option value="true">Active</option>
                    <option value="false">Inactive</option>
                </select>
            </div>
            <button type="submit" class="btn btn-secondary">Filter</button>
        </form>
    </div>

    <div id="supplier-list-table">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Supplier Code</th>
                    <th>Supplier Name</th>
                    <th>Contact Name</th>
                    <th>Email</th>
                    <th>Phone</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {{#records}}
                <tr>
                    <td>{{supplier_code}}</td>
                    <td>{{supplier_name}}</td>
                    <td>{{contact_name}}</td>
                    <td>{{email}}</td>
                    <td>{{phone}}</td>
                    <td>
                        {{#if is_active}}
                        <span class="badge badge-success">Active</span>
                        {{/if}}
                        {{#if not is_active}}
                        <span class="badge badge-secondary">Inactive</span>
                        {{/if}}
                    </td>
                    <td class="actions">
                        <button class="btn btn-sm btn-text"
                                hx-get="/ui/supplier/form/view?id={{supplier_id}}"
                                hx-target="#modal">
                            <i class="fa fa-eye"></i>
                        </button>
                        {{#if ../user_can_edit}}
                        <button class="btn btn-sm btn-text"
                                hx-get="/ui/supplier/form/edit?id={{supplier_id}}"
                                hx-target="#modal">
                            <i class="fa fa-edit"></i>
                        </button>
                        {{/if}}
                    </td>
                </tr>
                {{/records}}
            </tbody>
        </table>

        <div class="pagination">
            <span>Showing {{page_start}} to {{page_end}} of {{total_count}}</span>
            {{#if has_prev}}
            <button hx-get="/ui/supplier/list?page={{prev_page}}" hx-target="#supplier-list-table">Prev</button>
            {{/if}}
            {{#if has_next}}
            <button hx-get="/ui/supplier/list?page={{next_page}}" hx-target="#supplier-list-table">Next</button>
            {{/if}}
        </div>
    </div>
</div>',
    1,
    TRUE
) ON CONFLICT DO NOTHING;

-- =============================================================================
-- GOODS RECEIPT LIST TEMPLATE
-- =============================================================================

INSERT INTO htmx_templates (
    entity_type_id,
    view_type,
    template_name,
    base_template,
    version,
    is_active
) VALUES (
    '10000000-0000-0000-0000-000000000003'::UUID,
    'list',
    'Goods Receipt List View',
    '<div class="entity-list" data-entity="goods_receipt">
    <div class="list-header">
        <h2>{{entity_display_name}}</h2>
        <div class="list-actions">
            {{#if user_can_create}}
            <button class="btn btn-primary"
                    hx-get="/ui/goods_receipt/form/create"
                    hx-target="#modal">
                <i class="fa fa-plus"></i> Create Goods Receipt
            </button>
            {{/if}}
        </div>
    </div>

    <div class="list-filters">
        <form hx-get="/ui/goods_receipt/list"
              hx-target="#gr-list-table"
              hx-trigger="change, submit">
            <div class="filter-group">
                <select name="quality_status" multiple>
                    <option value="pending">Pending</option>
                    <option value="accepted">Accepted</option>
                    <option value="rejected">Rejected</option>
                </select>
            </div>
            <div class="filter-group">
                <input type="date" name="receipt_date_gte" placeholder="From date">
            </div>
            <div class="filter-group">
                <input type="date" name="receipt_date_lte" placeholder="To date">
            </div>
            <button type="submit" class="btn btn-secondary">Filter</button>
        </form>
    </div>

    <div id="gr-list-table">
        <table class="data-table">
            <thead>
                <tr>
                    <th>GR Number</th>
                    <th>PO Number</th>
                    <th>Receipt Date</th>
                    <th>Received By</th>
                    <th>Quality Status</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {{#records}}
                <tr>
                    <td>{{gr_number}}</td>
                    <td>{{po.po_number}}</td>
                    <td>{{receipt_date}}</td>
                    <td>{{received_by_name}}</td>
                    <td>
                        <span class="badge badge-{{quality_status}}">{{quality_status}}</span>
                    </td>
                    <td class="actions">
                        <button class="btn btn-sm btn-text"
                                hx-get="/ui/goods_receipt/form/view?id={{gr_id}}"
                                hx-target="#modal">
                            <i class="fa fa-eye"></i>
                        </button>
                        {{#if quality_status == ''pending''}}
                        {{#if ../user_can_approve}}
                        <button class="btn btn-sm btn-success"
                                hx-post="/api/goods_receipt/{{gr_id}}/accept"
                                hx-confirm="Accept this goods receipt?">
                            <i class="fa fa-check"></i>
                        </button>
                        <button class="btn btn-sm btn-danger"
                                hx-post="/api/goods_receipt/{{gr_id}}/reject"
                                hx-confirm="Reject this goods receipt?">
                            <i class="fa fa-times"></i>
                        </button>
                        {{/if}}
                        {{/if}}
                    </td>
                </tr>
                {{/records}}
            </tbody>
        </table>

        <div class="pagination">
            <span>Showing {{page_start}} to {{page_end}} of {{total_count}}</span>
            {{#if has_prev}}
            <button hx-get="/ui/goods_receipt/list?page={{prev_page}}" hx-target="#gr-list-table">Prev</button>
            {{/if}}
            {{#if has_next}}
            <button hx-get="/ui/goods_receipt/list?page={{next_page}}" hx-target="#gr-list-table">Next</button>
            {{/if}}
        </div>
    </div>
</div>',
    1,
    TRUE
) ON CONFLICT DO NOTHING;

-- =============================================================================
-- INVOICE RECEIPT LIST TEMPLATE
-- =============================================================================

INSERT INTO htmx_templates (
    entity_type_id,
    view_type,
    template_name,
    base_template,
    version,
    is_active
) VALUES (
    '10000000-0000-0000-0000-000000000004'::UUID,
    'list',
    'Invoice Receipt List View',
    '<div class="entity-list" data-entity="invoice_receipt">
    <div class="list-header">
        <h2>{{entity_display_name}}</h2>
        <div class="list-actions">
            {{#if user_can_create}}
            <button class="btn btn-primary"
                    hx-get="/ui/invoice_receipt/form/create"
                    hx-target="#modal">
                <i class="fa fa-plus"></i> Create Invoice
            </button>
            {{/if}}
        </div>
    </div>

    <div class="list-filters">
        <form hx-get="/ui/invoice_receipt/list"
              hx-target="#invoice-list-table"
              hx-trigger="change, submit">
            <div class="filter-group">
                <select name="matching_status" multiple>
                    <option value="pending">Pending</option>
                    <option value="matched">Matched</option>
                    <option value="variance">Variance</option>
                </select>
            </div>
            <div class="filter-group">
                <select name="payment_status" multiple>
                    <option value="unpaid">Unpaid</option>
                    <option value="partial">Partial</option>
                    <option value="paid">Paid</option>
                </select>
            </div>
            <button type="submit" class="btn btn-secondary">Filter</button>
        </form>
    </div>

    <div id="invoice-list-table">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Invoice Number</th>
                    <th>Vendor Invoice #</th>
                    <th>PO Number</th>
                    <th>Invoice Date</th>
                    <th>Total Amount</th>
                    <th>Matching Status</th>
                    <th>Payment Status</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {{#records}}
                <tr>
                    <td>{{invoice_number}}</td>
                    <td>{{vendor_invoice_number}}</td>
                    <td>{{po.po_number}}</td>
                    <td>{{invoice_date}}</td>
                    <td class="text-right">{{currency}} {{total_amount}}</td>
                    <td>
                        <span class="badge badge-{{matching_status}}">{{matching_status}}</span>
                    </td>
                    <td>
                        <span class="badge badge-{{payment_status}}">{{payment_status}}</span>
                    </td>
                    <td class="actions">
                        <button class="btn btn-sm btn-text"
                                hx-get="/ui/invoice_receipt/form/view?id={{invoice_id}}"
                                hx-target="#modal">
                            <i class="fa fa-eye"></i>
                        </button>
                        {{#if payment_status != ''paid''}}
                        {{#if ../user_can_create_payment}}
                        <button class="btn btn-sm btn-success"
                                hx-get="/ui/payment/form/create?invoice_id={{invoice_id}}"
                                hx-target="#modal">
                            <i class="fa fa-money"></i> Pay
                        </button>
                        {{/if}}
                        {{/if}}
                    </td>
                </tr>
                {{/records}}
            </tbody>
        </table>

        <div class="pagination">
            <span>Showing {{page_start}} to {{page_end}} of {{total_count}}</span>
            {{#if has_prev}}
            <button hx-get="/ui/invoice_receipt/list?page={{prev_page}}" hx-target="#invoice-list-table">Prev</button>
            {{/if}}
            {{#if has_next}}
            <button hx-get="/ui/invoice_receipt/list?page={{next_page}}" hx-target="#invoice-list-table">Next</button>
            {{/if}}
        </div>
    </div>
</div>',
    1,
    TRUE
) ON CONFLICT DO NOTHING;

-- =============================================================================
-- PAYMENT LIST TEMPLATE
-- =============================================================================

INSERT INTO htmx_templates (
    entity_type_id,
    view_type,
    template_name,
    base_template,
    version,
    is_active
) VALUES (
    '10000000-0000-0000-0000-000000000005'::UUID,
    'list',
    'Payment List View',
    '<div class="entity-list" data-entity="payment">
    <div class="list-header">
        <h2>{{entity_display_name}}</h2>
        <div class="list-actions">
            {{#if user_can_create}}
            <button class="btn btn-primary"
                    hx-get="/ui/payment/form/create"
                    hx-target="#modal">
                <i class="fa fa-plus"></i> Create Payment
            </button>
            {{/if}}
        </div>
    </div>

    <div class="list-filters">
        <form hx-get="/ui/payment/list"
              hx-target="#payment-list-table"
              hx-trigger="change, submit">
            <div class="filter-group">
                <select name="status" multiple>
                    <option value="pending">Pending</option>
                    <option value="processed">Processed</option>
                    <option value="cleared">Cleared</option>
                    <option value="failed">Failed</option>
                </select>
            </div>
            <div class="filter-group">
                <input type="date" name="payment_date_gte" placeholder="From date">
            </div>
            <button type="submit" class="btn btn-secondary">Filter</button>
        </form>
    </div>

    <div id="payment-list-table">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Payment Number</th>
                    <th>Invoice Number</th>
                    <th>Payment Date</th>
                    <th>Payment Method</th>
                    <th>Amount</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {{#records}}
                <tr>
                    <td>{{payment_number}}</td>
                    <td>{{invoice.invoice_number}}</td>
                    <td>{{payment_date}}</td>
                    <td>{{payment_method}}</td>
                    <td class="text-right">{{currency}} {{amount}}</td>
                    <td>
                        <span class="badge badge-{{status}}">{{status}}</span>
                    </td>
                    <td class="actions">
                        <button class="btn btn-sm btn-text"
                                hx-get="/ui/payment/form/view?id={{payment_id}}"
                                hx-target="#modal">
                            <i class="fa fa-eye"></i>
                        </button>
                        {{#if status == ''pending''}}
                        {{#if ../user_can_process}}
                        <button class="btn btn-sm btn-success"
                                hx-post="/api/payment/{{payment_id}}/process"
                                hx-confirm="Process this payment?">
                            <i class="fa fa-check"></i> Process
                        </button>
                        {{/if}}
                        {{/if}}
                    </td>
                </tr>
                {{/records}}
            </tbody>
        </table>

        <div class="pagination">
            <span>Showing {{page_start}} to {{page_end}} of {{total_count}}</span>
            {{#if has_prev}}
            <button hx-get="/ui/payment/list?page={{prev_page}}" hx-target="#payment-list-table">Prev</button>
            {{/if}}
            {{#if has_next}}
            <button hx-get="/ui/payment/list?page={{next_page}}" hx-target="#payment-list-table">Next</button>
            {{/if}}
        </div>
    </div>
</div>',
    1,
    TRUE
) ON CONFLICT DO NOTHING;

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Extended HTMX templates created successfully';
    RAISE NOTICE 'Created templates:';
    RAISE NOTICE '  - purchase_order form_edit';
    RAISE NOTICE '  - supplier list';
    RAISE NOTICE '  - goods_receipt list';
    RAISE NOTICE '  - invoice_receipt list';
    RAISE NOTICE '  - payment list';
END $$;
