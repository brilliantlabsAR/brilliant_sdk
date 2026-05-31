function fibonacci(n)
    if n <= 0 then
        return 0
    elseif n == 1 then
        return 1
    else
        local a = 0
        local b = 1
        for i = 2, n do
            local temp = a + b
            a = b
            b = temp
        end
        return b
    end
end
