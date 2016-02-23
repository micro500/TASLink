dumpfile = nil;

pollcount = 0;


--mapping = [0, 2, 1, 3, 4, 6, 5, 7];   -- p1d0, p1d1, p2d0, p2d1
--mapping = {0, 1, 2, 3, 4, 5, 6, 7};  -- p1i1, p1i0, p2i1, p2i0

----

start_dump = function(filename)
    fh, err = io.open(filename .. ".latch.r16m", "wb");
    if not fh then
        error("Error opening output file: " .. err);
    end
    print(string.format('Dumping to %s.latch.r16m', filename));
   
    dumpfile = fh;

    pollcount = 0;
end

stop_dump = function()
    if (dumpfile) then
        dumpfile:close();
        dumpfile = nil;
        print("Dumping halted")
    else
        print("Cannot stop: Dumping not started")
    end
end

on_latch = function()
    if dumpfile then
        pollcount = pollcount + 1
        tframe = movie.get_frame(movie.find_frame(movie.currentframe()));
        for i = 0, 7, 1 do
            out = 0
            for j = 0, 15, 1 do
                if tframe:get_button(1 + bit.rrotate(i, 2), i % 4, j) then
                    out = bit.bor(out, bit.value(15 - j))
                end
            end
            dumpfile:write(string.char(bit.band(bit.rrotate(out, 8), 0xff), bit.band(out, 0xff)));
        end
    end
end

on_paint = function()
    if dumpfile then
        gui.text(0, 0, pollcount, 0x00FF00, 0);
    end
end