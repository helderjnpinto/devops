-- Lua script for Fluent Bit to add correlation IDs
-- This script helps with distributed tracing by adding correlation IDs to logs

function add_correlation_id(tag, timestamp, record)
    -- Generate correlation ID if not present
    if not record['correlation_id'] then
        record['correlation_id'] = generate_uuid()
    end
    
    -- Add trace ID from headers if available
    if record['trace_id'] then
        record['trace_id'] = record['trace_id']
    end
    
    -- Add span ID if available
    if record['span_id'] then
        record['span_id'] = record['span_id']
    end
    
    return 1, timestamp, record
end

-- Simple UUID generator
function generate_uuid()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    local str = string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
    return str
end
