if (e.timer == "random") then
    local rand = math.random(1,100);
    local client_count = 0;
    local entity_list = eq.get_entity_list();
    local client_list = entity_list:GetClientList();

    if client_list ~= nil then
        for client in client_list.entries do
            if client.valid and not client:CastToMob():IsDead() then
                client_count = client_count + 1;
            end
        end
    end

    if (rand >= 85 and client_count >= 6) then
        local instance_id = eq.get_zone_instance_id();
        e.self:ForeachHateList(
            function(ent, hate, damage, frenzy)
                if(ent:IsClient() and ent:GetX() < 868) then
                    local currclient = ent:CastToClient();
                    e.self:Shout("You will not evade me " .. currclient:GetName());
                    currclient:MovePCInstance(294, instance_id, e.self:GetX(), e.self:GetY(), e.self:GetZ(), 0);
                end
            end
        );
        e.self:Emote("tosses its foes away wildly!");

        
        local throws = 0;
        if client_count >= 12 then
            throws = 3;
        elseif client_count >= 9 then
            throws = 2;
        else -- 
            throws = 1;
        end

        for i = 1, throws do
            e.self:CastedSpellFinished(4185, e.self:GetHateRandom()); -- Spell: Throw
        end

    elseif (rand < 85 and rand >= 70) then
        e.self:Emote("lets loose a bolt of energy toward his enemy!");
        e.self:CastedSpellFinished(1046, e.self:GetHateRandom());

    elseif (rand < 70 and rand >= 55) then
        local npc1 = eq.get_entity_list():GetMobByNpcTypeID(294466);
        local npc2 = eq.get_entity_list():GetMobByNpcTypeID(294469);

        if (npc1.valid and npc2.valid) then
            if (npc1:CalculateDistance(e.self:GetX(), e.self:GetY(), e.self:GetZ()) < npc2:CalculateDistance(e.self:GetX(), e.self:GetY(), e.self:GetZ())) then
                eq.signal(294466,1);
            else
                eq.signal(294469,1);
            end
        end
    end
end
