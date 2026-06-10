-- Repoint bulk_extractor at the full SIFT image (which actually ships it) and let it
-- accept a pcap/image/target arg. It now returns IOC histograms (emails/urls/ips) to stdout.
UPDATE tool_specs
SET image = 'find-evil-sleuth/sift-full:latest',
    timeout_s = 600,
    memory_mb = 4096,
    args_schema = '{
      "type": "object",
      "properties": {
        "image":  {"type": "string", "pattern": "^/case/"},
        "pcap":   {"type": "string", "pattern": "^/case/"},
        "target": {"type": "string", "pattern": "^/case/"}
      },
      "additionalProperties": false
    }'
WHERE tool = 'bulk_extractor';
