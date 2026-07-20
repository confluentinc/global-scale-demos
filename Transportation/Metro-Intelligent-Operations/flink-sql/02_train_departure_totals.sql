CREATE TABLE metro_train_departures
DISTRIBUTED INTO 1 BUCKETS
AS
SELECT
    window_start AS departure_window_start,
    window_end   AS departure_window_end,
    `metadata`.`metro_line`      AS metro_line,
    `metadata`.`direction`       AS direction,
    `metadata`.`train_id`        AS train_id,
    `location`.`current_station` AS current_station,
    `location`.`next_station`    AS next_station,
    SUM(`telemetry`.`headcount`) AS train_headcount,
    COUNT(*)                     AS coach_count
FROM TABLE(
    TUMBLE(TABLE `metro-camera-events`, DESCRIPTOR($rowtime), INTERVAL '1' MINUTE)
)
GROUP BY
    window_start,
    window_end,
    `metadata`.`metro_line`,
    `metadata`.`direction`,
    `metadata`.`train_id`,
    `location`.`current_station`,
    `location`.`next_station`;
