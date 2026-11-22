local T = require("./lib/T")
local Split = require("../src/shared/Rules/Split")

local SPAN = { from = 100, to = 192, buffer = 164, offset = 9, ramp = 28, open = -1 }

T.describe("Split", function()
    T.it("takes a side lane only when the crew leans far enough", function()
        T.equal(Split.lane(0), 0)
        T.equal(Split.lane(0.2), 0, "a half-hearted lean stays in the middle")
        T.equal(Split.lane(-0.2), 0)
        T.equal(Split.lane(1), 1)
        T.equal(Split.lane(-1), -1)
        T.equal(Split.lane(0.5), 1, "two of four leaning right is enough")
        T.equal(Split.lane(-0.5), -1)
    end)

    T.it("fans the side lanes out after the switch", function()
        for _, lane in { -1, 1 } do
            T.near(Split.offset(SPAN, lane, SPAN.from - 10), 0, 1e-9, "still on the line before the switch")
            T.near(Split.offset(SPAN, lane, SPAN.from), 0, 1e-9, "at the switch")
            T.near(Split.offset(SPAN, lane, SPAN.from + SPAN.ramp), lane * SPAN.offset, 1e-9, "fully out")
            local halfway = Split.offset(SPAN, lane, SPAN.from + SPAN.ramp / 2)
            T.truthy(math.abs(halfway) > 0 and math.abs(halfway) < SPAN.offset, "eases out")
        end
        T.equal(Split.offset(SPAN, 0, SPAN.from + 50), 0, "the middle lane is the line")
    end)

    T.it("brings the open lane back onto the line and leaves the dead ones out", function()
        T.near(Split.offset(SPAN, -1, SPAN.to), 0, 1e-9, "open lane rejoins")
        T.near(Split.offset(SPAN, 1, SPAN.buffer), SPAN.offset, 1e-9, "dead lane still out at its buffer")
        T.truthy(Split.dead(SPAN, 1) and Split.dead(SPAN, 0), "the other two are dead ends")
        T.falsy(Split.dead(SPAN, -1))
        T.equal(Split.railEnd(SPAN, -1), SPAN.to)
        T.equal(Split.railEnd(SPAN, 0), SPAN.buffer)
        T.equal(Split.railEnd(SPAN, 1), SPAN.buffer)
    end)
end)
