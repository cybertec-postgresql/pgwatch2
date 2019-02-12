ALTER TABLE metric
    ADD CONSTRAINT metric_m_name_check CHECK ((m_name ~ '^[a-z0-9_]+$'::text));
