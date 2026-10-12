-- Daily request counters. `subject` is a salted hash of a device ID or IP
-- address, or the literal "global". Nothing about request content is stored.
CREATE TABLE IF NOT EXISTS usage (
  day TEXT NOT NULL,
  subject TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, subject)
);
