-- Migration 003: Create Audit and Performance Tables
-- Description: Creates logging and monitoring tables for performance tracking
-- Dependencies: 002_create_ui_framework.sql
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- UI GENERATION LOGS TABLE
-- =============================================================================
-- Logs every UI generation request for performance monitoring and debugging

CREATE TABLE ui_generation_logs (
    log_id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id              UUID NOT NULL,
    user_id                 UUID,
    entity_type             VARCHAR(100) NOT NULL,
    view_type               VARCHAR(50) NOT NULL,
    generation_start_time   TIMESTAMPTZ NOT NULL,
    generation_end_time     TIMESTAMPTZ,
    duration_ms             INTEGER,
    template_cache_hit      BOOLEAN DEFAULT FALSE,
    permission_cache_hit    BOOLEAN DEFAULT FALSE,
    data_row_count          INTEGER,
    output_size_bytes       INTEGER,
    error_message           TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_gen_log_user FOREIGN KEY (user_id)
        REFERENCES users(user_id),
    CONSTRAINT chk_gen_log_view_type CHECK (view_type IN (
        'list', 'form_create', 'form_edit', 'form_view', 'filter_panel', 'detail'
    )),
    CONSTRAINT chk_gen_log_duration CHECK (
        duration_ms IS NULL OR duration_ms >= 0
    ),
    CONSTRAINT chk_gen_log_row_count CHECK (
        data_row_count IS NULL OR data_row_count >= 0
    ),
    CONSTRAINT chk_gen_log_output_size CHECK (
        output_size_bytes IS NULL OR output_size_bytes >= 0
    )
);

COMMENT ON TABLE ui_generation_logs IS 'Logs every UI generation request for performance monitoring';
COMMENT ON COLUMN ui_generation_logs.request_id IS 'Unique identifier for this generation request';
COMMENT ON COLUMN ui_generation_logs.duration_ms IS 'Total time taken to generate UI in milliseconds';
COMMENT ON COLUMN ui_generation_logs.template_cache_hit IS 'Whether template was retrieved from cache';
COMMENT ON COLUMN ui_generation_logs.permission_cache_hit IS 'Whether permissions were retrieved from cache';
COMMENT ON COLUMN ui_generation_logs.error_message IS 'Error details if generation failed';

-- Indexes for ui_generation_logs
CREATE INDEX idx_gen_log_user ON ui_generation_logs(user_id);
CREATE INDEX idx_gen_log_entity ON ui_generation_logs(entity_type);
CREATE INDEX idx_gen_log_view_type ON ui_generation_logs(view_type);
CREATE INDEX idx_gen_log_start_time ON ui_generation_logs(generation_start_time);
CREATE INDEX idx_gen_log_duration ON ui_generation_logs(duration_ms) WHERE duration_ms IS NOT NULL;
CREATE INDEX idx_gen_log_errors ON ui_generation_logs(error_message) WHERE error_message IS NOT NULL;
CREATE INDEX idx_gen_log_request ON ui_generation_logs(request_id);

-- Composite index for common performance queries
CREATE INDEX idx_gen_log_entity_view_time ON ui_generation_logs(
    entity_type, view_type, generation_start_time
);

-- =============================================================================
-- PERFORMANCE METRICS TABLE
-- =============================================================================
-- Aggregated performance metrics for dashboards and monitoring

CREATE TABLE performance_metrics (
    metric_id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    metric_timestamp        TIMESTAMPTZ NOT NULL,
    endpoint_name           VARCHAR(200) NOT NULL,
    avg_response_time_ms    DECIMAL(10,2),
    p95_response_time_ms    DECIMAL(10,2),
    p99_response_time_ms    DECIMAL(10,2),
    request_count           INTEGER NOT NULL DEFAULT 0,
    error_count             INTEGER NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_perf_avg_response CHECK (
        avg_response_time_ms IS NULL OR avg_response_time_ms >= 0
    ),
    CONSTRAINT chk_perf_p95_response CHECK (
        p95_response_time_ms IS NULL OR p95_response_time_ms >= 0
    ),
    CONSTRAINT chk_perf_p99_response CHECK (
        p99_response_time_ms IS NULL OR p99_response_time_ms >= 0
    ),
    CONSTRAINT chk_perf_request_count CHECK (request_count >= 0),
    CONSTRAINT chk_perf_error_count CHECK (error_count >= 0)
);

COMMENT ON TABLE performance_metrics IS 'Aggregated performance metrics for monitoring and dashboards';
COMMENT ON COLUMN performance_metrics.endpoint_name IS 'API endpoint or function name';
COMMENT ON COLUMN performance_metrics.p95_response_time_ms IS '95th percentile response time';
COMMENT ON COLUMN performance_metrics.p99_response_time_ms IS '99th percentile response time';

-- Indexes for performance_metrics
CREATE INDEX idx_perf_timestamp ON performance_metrics(metric_timestamp);
CREATE INDEX idx_perf_endpoint ON performance_metrics(endpoint_name);
CREATE INDEX idx_perf_endpoint_time ON performance_metrics(endpoint_name, metric_timestamp);

-- =============================================================================
-- HELPER VIEW: Recent Performance Dashboard
-- =============================================================================
-- Materialized view for quick access to recent performance data

CREATE MATERIALIZED VIEW performance_dashboard AS
SELECT
    entity_type,
    view_type,
    COUNT(*) as request_count,
    AVG(duration_ms) as avg_duration_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms) as p95_duration_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99_duration_ms,
    MIN(duration_ms) as min_duration_ms,
    MAX(duration_ms) as max_duration_ms,
    AVG(data_row_count) as avg_row_count,
    SUM(CASE WHEN error_message IS NOT NULL THEN 1 ELSE 0 END) as error_count,
    SUM(CASE WHEN template_cache_hit THEN 1 ELSE 0 END)::DECIMAL / COUNT(*) * 100 as template_cache_hit_rate,
    SUM(CASE WHEN permission_cache_hit THEN 1 ELSE 0 END)::DECIMAL / COUNT(*) * 100 as permission_cache_hit_rate,
    MAX(generation_start_time) as last_request_time
FROM ui_generation_logs
WHERE generation_start_time > NOW() - INTERVAL '1 hour'
  AND duration_ms IS NOT NULL
GROUP BY entity_type, view_type;

COMMENT ON MATERIALIZED VIEW performance_dashboard IS 'Last hour performance metrics by entity and view type';

-- Create index on materialized view
CREATE UNIQUE INDEX idx_perf_dash_entity_view ON performance_dashboard(entity_type, view_type);

-- =============================================================================
-- AUDIT TRAIL TABLE (Optional - for tracking all data changes)
-- =============================================================================
-- Generic audit trail for tracking changes to any table

CREATE TABLE audit_trail (
    audit_id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name          VARCHAR(100) NOT NULL,
    record_id           UUID NOT NULL,
    operation           VARCHAR(10) NOT NULL,
    old_values          JSONB,
    new_values          JSONB,
    changed_by          UUID,
    changed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_audit_changed_by FOREIGN KEY (changed_by)
        REFERENCES users(user_id),
    CONSTRAINT chk_audit_operation CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE'))
);

COMMENT ON TABLE audit_trail IS 'Generic audit trail for tracking all data changes';
COMMENT ON COLUMN audit_trail.table_name IS 'Name of table that was modified';
COMMENT ON COLUMN audit_trail.record_id IS 'Primary key of modified record';
COMMENT ON COLUMN audit_trail.old_values IS 'JSONB snapshot of values before change';
COMMENT ON COLUMN audit_trail.new_values IS 'JSONB snapshot of values after change';

-- Indexes for audit_trail
CREATE INDEX idx_audit_table ON audit_trail(table_name);
CREATE INDEX idx_audit_record ON audit_trail(record_id);
CREATE INDEX idx_audit_changed_at ON audit_trail(changed_at);
CREATE INDEX idx_audit_changed_by ON audit_trail(changed_by);
CREATE INDEX idx_audit_table_record ON audit_trail(table_name, record_id);

-- =============================================================================
-- FUNCTION: Refresh Performance Dashboard
-- =============================================================================
-- Helper function to refresh the materialized view

CREATE OR REPLACE FUNCTION refresh_performance_dashboard()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY performance_dashboard;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_performance_dashboard() IS 'Refreshes the performance dashboard materialized view';

-- =============================================================================
-- FUNCTION: Cleanup Old Logs
-- =============================================================================
-- Helper function to archive/delete old logs to manage table size

CREATE OR REPLACE FUNCTION cleanup_old_logs(p_retention_days INTEGER DEFAULT 90)
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    -- Delete logs older than retention period
    DELETE FROM ui_generation_logs
    WHERE generation_start_time < NOW() - (p_retention_days || ' days')::INTERVAL;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    RAISE NOTICE 'Deleted % log records older than % days', v_deleted_count, p_retention_days;

    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_old_logs(INTEGER) IS 'Deletes log records older than specified days (default: 90)';

-- =============================================================================
-- FUNCTION: Get Performance Summary
-- =============================================================================
-- Quick function to get performance stats for an entity

CREATE OR REPLACE FUNCTION get_performance_summary(
    p_entity_type VARCHAR,
    p_hours_back INTEGER DEFAULT 24
)
RETURNS TABLE (
    view_type VARCHAR,
    request_count BIGINT,
    avg_duration_ms NUMERIC,
    p95_duration_ms NUMERIC,
    error_rate NUMERIC,
    cache_hit_rate NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        l.view_type::VARCHAR,
        COUNT(*) as request_count,
        ROUND(AVG(l.duration_ms)::NUMERIC, 2) as avg_duration_ms,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY l.duration_ms)::NUMERIC, 2) as p95_duration_ms,
        ROUND((SUM(CASE WHEN l.error_message IS NOT NULL THEN 1 ELSE 0 END)::NUMERIC / COUNT(*) * 100), 2) as error_rate,
        ROUND((SUM(CASE WHEN l.template_cache_hit THEN 1 ELSE 0 END)::NUMERIC / COUNT(*) * 100), 2) as cache_hit_rate
    FROM ui_generation_logs l
    WHERE l.entity_type = p_entity_type
      AND l.generation_start_time > NOW() - (p_hours_back || ' hours')::INTERVAL
      AND l.duration_ms IS NOT NULL
    GROUP BY l.view_type
    ORDER BY request_count DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_performance_summary(VARCHAR, INTEGER) IS 'Get performance summary for an entity over specified hours';

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 003 completed successfully';
    RAISE NOTICE 'Created 3 audit/performance tables: ui_generation_logs, performance_metrics, audit_trail';
    RAISE NOTICE 'Created materialized view: performance_dashboard';
    RAISE NOTICE 'Created helper functions: refresh_performance_dashboard, cleanup_old_logs, get_performance_summary';
END $$;
