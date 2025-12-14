-- Simple FIFO Linked List Queue in Lua
--> fifoq = 1; s();

_G.Queue = {}
Queue.__index = Queue;

function Queue.new(tab)
    return setmetatable(tab or {first = nil, last = nil}, Queue);
end

function Queue:push(value)
    local node = value or {next = nil};
    if not self.first then
        -- Queue is empty
        self.first = node
        self.last = node
    else
        -- Append to the end
        self.last.next = node
        self.last = node
    end
end

function Queue:pop()
    if not self.first then
        return nil -- Queue is empty
    end
    local first = self.first
    self.first = first.next
    if not self.first then
        self.last = nil -- Queue is now empty
    end
    return first
end

function Queue:empty()
    return self.first == nil
end