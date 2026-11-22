local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Jump = require("../src/shared/Rules/Jump")

local physics = Configs.Run.Cart.Jump
local GAP = { length = 30, drop = 8 }

T.describe("Jump", function()
    T.it("only just makes the far side at the slowest speed", function()
        local slowest = Jump.minSpeed(physics, GAP)
        T.near(Jump.height(physics, slowest, GAP.length), -(GAP.drop + physics.Clearance), 1e-9)
    end)

    T.it("clears faster and falls in slower", function()
        local slowest = Jump.minSpeed(physics, GAP)
        T.truthy(Jump.clears(physics, GAP, slowest + 0.01), "faster clears")
        T.falsy(Jump.clears(physics, GAP, slowest - 0.01), "slower falls in")
        T.falsy(Jump.clears(physics, GAP, 0), "a stopped cart falls in")
        T.truthy(
            Jump.height(physics, slowest + 5, GAP.length) > Jump.height(physics, slowest, GAP.length),
            "faster flies higher at the far edge"
        )
    end)

    T.it("needs more speed for wider gaps and bigger drops help", function()
        local wide = { length = 40, drop = 8 }
        local deep = { length = 30, drop = 14 }
        T.truthy(Jump.minSpeed(physics, wide) > Jump.minSpeed(physics, GAP), "wider is harder")
        T.truthy(Jump.minSpeed(physics, deep) < Jump.minSpeed(physics, GAP), "a deeper landing is easier")
    end)

    T.it("lands on the far deck, past the edge when flying fast", function()
        local fast = Jump.minSpeed(physics, GAP) * 1.3
        local landing = Jump.landing(physics, GAP, fast)
        T.truthy(landing > GAP.length, "lands past the edge")
        T.near(Jump.height(physics, fast, landing), -GAP.drop, 1e-6)
        local just = Jump.minSpeed(physics, GAP) + 0.01
        T.equal(Jump.landing(physics, GAP, just), GAP.length, "only just making it sets down on the edge")
    end)

    T.it("lands with a bounce: smaller hops each time, then still", function()
        local fast = Jump.minSpeed(physics, GAP) * 1.2
        local impact = Jump.impact(physics, fast, Jump.landing(physics, GAP, fast))
        T.truthy(impact > 5, "it comes down hard enough to feel, got " .. impact)
        local hopSpeed, pitchSpeed, rollSpeed = Jump.landingKick(physics, impact, 1)
        T.truthy(hopSpeed > 0, "bounces up")
        T.truthy(pitchSpeed < 0, "nose slams down")
        T.truthy(rollSpeed > 0, "jolts toward the side asked for")
        local _, _, other = Jump.landingKick(physics, impact, -1)
        T.truthy(other < 0, "and the other side")

        local height, speed = 0, hopSpeed
        local peaks, highest, wasRising = {}, 0, true
        local frames = 0
        while (height > 0 or speed > 0) and frames < 600 do
            height, speed = Jump.bounce(physics, height, speed, 1 / 60)
            T.truthy(height >= 0, "never sinks into the rails")
            highest = math.max(highest, height)
            if wasRising and speed <= 0 and height > 0 then
                table.insert(peaks, height)
            end
            wasRising = speed > 0
            frames += 1
        end
        T.truthy(#peaks >= 1, "at least one hop")
        for index = 2, #peaks do
            T.truthy(peaks[index] < peaks[index - 1], "each hop is smaller")
        end
        T.truthy(frames < 600, "comes to rest")
        T.truthy(highest < 3, "a bounce, not a second jump: " .. highest)
    end)

    T.it("lands harder off a bigger drop", function()
        local fast = Jump.minSpeed(physics, GAP) * 1.2
        local deep = { length = GAP.length, drop = GAP.drop * 2 }
        T.truthy(
            Jump.impact(physics, fast, Jump.landing(physics, deep, fast))
                > Jump.impact(physics, fast, Jump.landing(physics, GAP, fast))
        )
    end)

    T.it("leaves the lip nose up and comes down nose down", function()
        local speed = Jump.minSpeed(physics, GAP)
        T.near(Jump.slope(physics, speed, 0), math.tan(math.rad(physics.Lip)), 1e-9)
        T.truthy(Jump.slope(physics, speed, GAP.length) < 0, "falling by the far edge")
        T.truthy(Jump.time(physics, speed, GAP.length) > 0)
    end)
end)
