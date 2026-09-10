CREATE OR REPLACE FUNCTION generate_telco_batch(p_window_seconds int DEFAULT 5)
RETURNS void AS

\[
DECLARE
    base_ts   timestamptz := date_trunc('second', now());
    win_start timestamptz := base_ts;
    win_end   timestamptz := base_ts + (p_window_seconds || ' seconds')::interval;

    -- Tracking areas
    ta_1001   int := 1;  -- good
    ta_1002   int := 2;  -- good
    ta_2001   int := 3;  -- bad underlay, bad SGW_03 calls
    ta_2002   int := 4;  -- good

    -- Serving gateways
    sgw_01    int := 1;  -- good
    sgw_02    int := 2;  -- good
    sgw_03    int := 3;  -- bad
    sgw_04    int := 4;  -- good

    -- Serving switches (all “good” for simplicity)
    sw_1      int := 1;
    sw_2      int := 2;

    -- KPIs: RAN/Core good everywhere
    ran_attach  numeric(5,2) := random() * 0.5 + 99.5;  -- Random value between 99.5 and 100
    ran_call    numeric(5,2) := random() * 0.5 + 99.0;  -- Random value between 99.0 and 99.5
    ran_ho      numeric(5,2) := random() * 0.5 + 98.5;  -- Random value between 98.5 and 99.0

    core_attach numeric(5,2) := random() * 0.3 + 99.7;  -- Random value between 99.7 and 100.0
    core_call   numeric(5,2) := random() * 0.3 + 99.3;  -- Random value between 99.3 and 99.6
    core_ho     numeric(5,2) := random() * 0.3 + 99.0;  -- Random value between 99.0 and 99.3

    -- Underlay good vs bad
    pkt_loss_good numeric(5,2)  := random() * 0.4 + 0.1;  -- Random value between 0.1 and 0.5
    lat_good      numeric(10,2) := random() * 90 + 10;   -- Random value between 10 and 100
    jit_good      numeric(10,2) := random() * 2 + 3;      -- Random value between 3 and 5

    pkt_loss_bad  numeric(5,2)  := random() * 4.9 + 5.0; -- Random value between 5.0 and 9.9
    lat_bad       numeric(10,2) := random() * 199 + 201;   -- Random value between 201 and 400
    jit_bad       numeric(10,2) := random() * 470 + 30;     -- Random value between 30 and 500
BEGIN
    -- 1) RAN & Core performance – good in ALL tracking areas

    -- TA_1001
    INSERT INTO telco.fact_ran_performance (
        window_start_ts, window_end_ts, tracking_area_id,
        ran_attach_success_rate, ran_call_success_rate, ran_handover_success_rate
    ) VALUES (win_start, win_end, ta_1001, ran_attach, ran_call, ran_ho);

    INSERT INTO telco.fact_core_performance (
        window_start_ts, window_end_ts, tracking_area_id,
        core_attach_success_rate, core_call_success_rate, core_handover_success_rate
    ) VALUES (win_start, win_end, ta_1001, core_attach, core_call, core_ho);

    -- TA_1002
    INSERT INTO telco.fact_ran_performance
    VALUES (win_start, win_end, ta_1002, ran_attach, ran_call, ran_ho);

    INSERT INTO telco.fact_core_performance
    VALUES (win_start, win_end, ta_1002, core_attach, core_call, core_ho);

    -- TA_2001 (bad underlay, but RAN/Core still look good)
    INSERT INTO telco.fact_ran_performance
    VALUES (win_start, win_end, ta_2001, ran_attach, ran_call, ran_ho);

    INSERT INTO telco.fact_core_performance
    VALUES (win_start, win_end, ta_2001, core_attach, core_call, core_ho);

    -- TA_2002
    INSERT INTO telco.fact_ran_performance
    VALUES (win_start, win_end, ta_2002, ran_attach, ran_call, ran_ho);

    INSERT INTO telco.fact_core_performance
    VALUES (win_start, win_end, ta_2002, core_attach, core_call, core_ho);

    -- 2) Underlay: TA_2001 bad, others good

    -- TA_1001
    INSERT INTO telco.fact_underlay_performance (
        window_start_ts, window_end_ts, tracking_area_id,
        packet_loss_pct, latency_ms, jitter_ms
    ) VALUES (win_start, win_end, ta_1001,
              pkt_loss_good, lat_good, jit_good);

    -- TA_1002
    INSERT INTO telco.fact_underlay_performance
    VALUES (win_start, win_end, ta_1002,
            pkt_loss_good, lat_good, jit_good);

    -- TA_2001 (bad)
    INSERT INTO telco.fact_underlay_performance
    VALUES (win_start, win_end, ta_2001,
            pkt_loss_bad, lat_bad, jit_bad);

    -- TA_2002
    INSERT INTO telco.fact_underlay_performance
    VALUES (win_start, win_end, ta_2002,
            pkt_loss_good, lat_good, jit_good);

    -- 3) Subscriber state snapshots (optional, just to have data)

    INSERT INTO telco.fact_subscriber_state (imsi, snapshot_ts, vlr, calling_state)
    VALUES
      -- good TAs
      ('502120000000001', win_start, 'VLR_1001', 'ACTIVE'),
      ('502120000000002', win_start, 'VLR_1001', 'ACTIVE'),
      ('502120000000003', win_start, 'VLR_1002', 'ACTIVE'),
      ('502120000000004', win_start, 'VLR_1002', 'ACTIVE'),
      ('502120000000005', win_start, 'VLR_2002', 'ACTIVE'),
      ('502120000000006', win_start, 'VLR_2002', 'ACTIVE'),
      ('502120000000007', win_start, 'VLR_1001', 'ACTIVE'),
      ('502120000000008', win_start, 'VLR_1002', 'ACTIVE'),
      -- bad TA
      ('502120000000009', win_start, 'VLR_2001', 'ACTIVE'),
      ('502120000000010', win_start, 'VLR_2001', 'ACTIVE');

    -- 4) Calls
    -- IMSI 1–8: always in GOOD TAs, GOOD SGWs, NORMAL_CLEARING
    -- IMSI 9–10: in TA_2001 and SGW_03, BAD clear codes

    -- Good calls (IMSI 1–8)
    INSERT INTO telco.fact_call_clear_code (
        imsi, tracking_area_id, serving_gateway_id, serving_switch_id,
        start_ts, end_ts, clear_code
    ) VALUES
      ('502120000000001', ta_1001, sgw_01, sw_1,
       win_start, win_end,
       'NORMAL_CLEARING'),
      ('502120000000002', ta_1001, sgw_01, sw_1,
       win_start, win_end,
       'NORMAL_CLEARING'),
      ('502120000000003', ta_1002, sgw_02, sw_1,
       win_start, win_end,
       'NORMAL_CLEARING'),
      ('502120000000004', ta_1002, sgw_02, sw_1,
       win_start, win_end,
       'NORMAL_CLEARING'),
      ('502120000000005', ta_2002, sgw_04, sw_2,
       win_start, win_end,
       'NORMAL_CLEARING'),
      ('502120000000006', ta_2002, sgw_04, sw_2,
       win_start, win_end,
       'NORMAL_CLEARING'),
      ('502120000000007', ta_1001, sgw_01, sw_1,
       win_start, win_end,
       'NORMAL_CLEARING'),
      ('502120000000008', ta_1002, sgw_02, sw_1,
       win_start, win_end,
       'NORMAL_CLEARING');

    -- Bad calls (IMSI 9–10) – TA_2001, SGW_03
    INSERT INTO telco.fact_call_clear_code (
        imsi, tracking_area_id, serving_gateway_id, serving_switch_id,
        start_ts, end_ts, clear_code
    ) VALUES
      ('502120000000009', ta_2001, sgw_03, sw_2,
       win_start, win_end,
       'SGW_CONGESTION_FAILURE'),
      ('502120000000010', ta_2001, sgw_03, sw_2,
       win_start, win_end,
       'SGW_INTERNAL_ERROR');
END;
\]
 LANGUAGE plpgsql;