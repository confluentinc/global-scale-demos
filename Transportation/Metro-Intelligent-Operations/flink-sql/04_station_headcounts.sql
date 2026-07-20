CREATE TABLE metro_station_headcounts
DISTRIBUTED INTO 1 BUCKETS
AS
SELECT
    window_start AS agg_window_start,
    window_end   AS agg_window_end,
    metro_line,
    direction,
    current_station,
    SUM(train_headcount)     AS total_headcount,
    COUNT(DISTINCT train_id) AS active_trains
FROM TABLE(
    TUMBLE(TABLE metro_train_departures, DESCRIPTOR($rowtime), INTERVAL '5' MINUTE)
)
GROUP BY
    window_start,
    window_end,
    metro_line,
    direction,
    current_station;
