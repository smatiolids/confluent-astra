CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY,
  event_time timestamp,
  payload text
);

-- Optional verification query
-- SELECT * FROM messages LIMIT 10;
