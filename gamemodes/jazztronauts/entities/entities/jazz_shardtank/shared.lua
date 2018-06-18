AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
ENT.Model = "models/sunabouzu/shard_tank.mdl"

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "CollectedShards")
	self:NetworkVar("Int", 1, "TotalShards")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(self.Model)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)

        self:SetSequence(self:LookupSequence("Fill_Tank"))

        self:SetCollectedShards(progress.GetMapShardCount())
        self:SetTotalShards(100) -- #TODO??
    end

else
    ENT.TankAmbientSound = "ambient/water/water_in_boat1.wav"
    ENT.TankSplashSounds = {
        "ambient/water/water_splash1.wav",
        "ambient/water/water_splash2.wav",
        "ambient/water/water_splash3.wav"
    }
    ENT.TankIncreaseSound = "jazztronauts/honks/vaaaa.wav"

    ENT.FinishedAnimation = false
    ENT.AnimationStartShards = 0
    ENT.AnimShardCount = 0
    ENT.AnimShardRate = 8 --shards per second to drop into shard soup

    ENT.GoalCompletePercent = 0

    local sizeX = 256
    local sizeY = 256
    local screen_rt = irt.New("jazz_shardtank_screen", sizeX, sizeY)

    surface.CreateFont( "JazzShardTankFont", {
        font = "KG Shake it Off Chunky",
        extended = false,
        size = 65,
        weight = 500,
        antialias = true,
    } )

    surface.CreateFont( "JazzShardTankSubtextFont", {
        font = "KG Shake it Off Chunky",
        extended = false,
        size = 25,
        weight = 500,
        antialias = true,
    } )

    function ENT:Initialize()
        self:SetSequence(self:LookupSequence("Fill_Tank"))
    end

    function ENT:CheckSound()
        
        if not self.TankAmbient then
            self.TankAmbient = CreateSound(self, self.TankAmbientSound) 
            self.TankAmbient:SetSoundLevel(60)
            self.TankAmbient:Play()
            self.TankAmbient:ChangePitch(45)
            self.TankAmbient:ChangeVolume(0)
        else
            //self.TankAmbient:Stop()
            //self.TankAmbient = nil
        end
    end

    function ENT:OnRemove()
        if self.TankAmbient then
            self.TankAmbient:Stop()
            self.TankAmbient = nil
        end
    end

    function ENT:GetCollectedShardCount()
        return self.AnimShardCount
    end

    function ENT:GetLiquidLevel()
        return self:GetPos() + Vector(0, 0, 1) * self:GetCompletePercent() * 110 + Vector(0, 0, 10)
    end

    function ENT:GetCompletePercent()
        local c = self:GetCollectedShardCount()
        local t = self.GetTotalShards and self:GetTotalShards() or 0

        return c * 1.0 / t
    end

    function ENT:DoShardAnimation(delay)
        coroutine.wait(delay)

        local shard = ManagedCSEnt("jazz_shardtank_" .. delay, "models/sunabouzu/jazzshard.mdl")
        shard:SetNoDraw(false)
        shard:SetPos(self:GetPos() + Vector(0, 0, 400))
        shard:SetAngles(AngleRand())
        local t = 0
        local endt = 1.0
        while t < endt do
            t = t + FrameTime() 
            local p = t / endt
            local pos = 400 * (1 - math.pow(p, 2))

            shard:SetPos(self:GetPos() + Vector(0, 0, pos))
            coroutine.yield()
        end

        shard:SetNoDraw(true)

        self.AnimShardCount = math.Approach(self.AnimShardCount, self:GetCollectedShards(), 1)

        local waterLevel = self:GetLiquidLevel()

        local completePerc = self:GetCompletePercent()
        if self.TankAmbient then
            self.TankAmbient:ChangeVolume(math.min(1, completePerc * 4))
        end

        -- Sound effects
        self:EmitSound(table.Random(self.TankSplashSounds), 75)
        self:EmitSound(self.TankIncreaseSound, 75, 50 + completePerc * 60)
        
        -- Splash effect
        local effectdata = EffectData()
        effectdata:SetOrigin( waterLevel )
        effectdata:SetMagnitude(4)
        effectdata:SetScale(0.25)
        effectdata:SetRadius(0.25)
        effectdata:SetEntity(self)
        util.Effect("ElectricSpark", effectdata)
        
    end

    function ENT:DoAllShardAnimation()
        local curShards = self.AnimShardCount
        local numShards = self:GetCollectedShards()
        local numIterations = 0
        self.AnimCoroutines = self.AnimCoroutines or {}
        while curShards != numShards do
            curShards = math.Approach(curShards, numShards, 1)
            numIterations = numIterations + 1

            local delay = 3 + numIterations / self.AnimShardRate
            local co = coroutine.create(self.DoShardAnimation)
            table.insert(self.AnimCoroutines, co)
            coroutine.resume(co, self, delay)
        end
    end

    function ENT:TickAnimCoroutines()
        if not self.AnimCoroutines then return end
        for i=#self.AnimCoroutines, 1, -1 do
            local co = self.AnimCoroutines[i]
            local succ, err
            succ = coroutine.status(co) != "dead"
            if succ then
                succ, err = coroutine.resume(co)
            end

            if not succ then 
                if err then ErrorNoHalt(err) end
                table.remove(self.AnimCoroutines, i)
            end
        end
    end

    function ENT:Think()
        if not self.AnimCoroutines or #self.AnimCoroutines == 0 then
            if self.AnimShardCount != self:GetCollectedShards() then
                self:DoAllShardAnimation()
            end
        end
        self:TickAnimCoroutines()
        self:CheckSound()

        self.GoalCompletePercent = math.Approach(self.GoalCompletePercent or 0, self:GetCompletePercent(), FrameTime() * 0.1)
        self:SetCycle(self.GoalCompletePercent + math.sin(CurTime() * 2) * 0.007)

        //self.AnimShardCount = math.Approach(self.AnimShardCount, self:GetCollectedShards(), 1)
    end

    function ENT:DrawRTScreen()
        screen_rt:Render(function()
            local c = HSVToColor(math.NormalizeAngle(CurTime() * 40), 0.8, 0.5)
            render.Clear(c.r, c.g, c.b, 255)
            cam.Start2D()
                local ctext = self:GetCollectedShardCount() .. " shards"
                local ntext = (self.GetTotalShards and self:GetTotalShards() or "") .. " needed"

                draw.SimpleText(ctext, "JazzShardTankFont", sizeX / 2, sizeY / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(ntext, "JazzShardTankSubtextFont", sizeX / 2, sizeY / 1.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)  
            cam.End2D()
		end)
    end

    function ENT:Draw()
        self:DrawRTScreen()
        render.MaterialOverrideByIndex(3, screen_rt:GetUnlitMaterial())
        self:DrawModel()
        render.MaterialOverrideByIndex(3, nil)
    end
end