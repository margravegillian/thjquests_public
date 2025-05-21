###########################################
## Main Event Handlers
###########################################

sub EVENT_SPAWN {
    $npc->SetTimer("cast_check", 1);
}

sub EVENT_TIMER {
    if ($timer eq "cast_check") {
        handle_cast_check();
    } elsif ($timer =~ /^recast_blocker_expire_(\d+)$/) {
        my $spell_id = $1;
        quest::debug("Cooldown expired for spell $spell_id");
        $npc->DeleteEntityVariable("recast_blocker_$spell_id");
        $npc->StopTimer($timer);
    } elsif ($timer eq "global_cooldown_expire") {
        quest::debug("Global cooldown expired");
        $npc->DeleteEntityVariable("global_cooldown");
        $npc->StopTimer($timer);
    }
}

sub EVENT_CAST {
    quest::debug("spell_id " . $spell_id);
    quest::debug("caster_id " . $caster_id);
    quest::debug("caster_level " . $caster_level);
    quest::debug("target_id " . $target_id);
    quest::debug("target " . $target);
    quest::debug("spell " . $spell);

    handle_post_cast($spell_id);
}

###########################################
## Main Casting Logic
###########################################

sub handle_cast_check {
    quest::debug("Checking if we can cast");
    
    # Skip if already casting
    if ($npc->IsCasting()) {
        quest::debug("Already casting, skipping");
        return;
    }
    
    # Check for global cooldown
    if ($npc->GetEntityVariable("global_cooldown") eq "true") {
        quest::debug("Global cooldown active, skipping cast check");
        return;
    }
    
    # Get owner and target
    my $owner = $entity_list->GetClientByID($npc->GetSwarmOwner());
    my $target = $npc->GetTarget();
    
    if (!$owner) {
        quest::debug("No owner found, skipping cast");
        return;
    }
    
    # Get memorized spells
    my @memmed_spells = $owner->GetMemmedSpells();
    quest::debug("Total memorized spells: " . scalar(@memmed_spells));
    
    # Split and sort spells by type
    my @beneficial_spells = get_sorted_beneficial_spells(@memmed_spells);
    my @harmful_spells = get_sorted_harmful_spells(@memmed_spells);
    
    quest::debug("Beneficial spells: " . scalar(@beneficial_spells) . ", Harmful spells: " . scalar(@harmful_spells));
    
    # First try to cast a beneficial spell on owner, group members, or pets
    if (try_cast_beneficial_spell($owner, @beneficial_spells)) {
        return; # Spell was cast, done for this round
    }
    
    # If no beneficial spell was cast and we have a target, try harmful spells
    if ($target && try_cast_harmful_spell($target, @harmful_spells)) {
        return; # Spell was cast, done for this round
    }
    
    # If we get here, no spell was cast
    quest::debug("No suitable spell found to cast");
}

sub handle_post_cast {
    my $spell_id = shift;
    my $spell_obj = quest::getspell($spell_id);
    
    # Handle the specific spell's recast time
    my $recast_time = $spell_obj->GetRecastTime();
    if ($recast_time > 0) {
        quest::debug("Setting spell cooldown for $spell_id: $recast_time ms");
        $npc->SetEntityVariable("recast_blocker_$spell_id", "true");
        my $recast_seconds = $recast_time / 1000;
        $npc->SetTimer("recast_blocker_expire_$spell_id", $recast_seconds);
    }
    
    # Handle the global cooldown (recovery time)
    my $recovery_time = $spell_obj->GetRecoveryTime();
    if ($recovery_time > 0) {
        quest::debug("Setting global cooldown: $recovery_time ms");
        $npc->SetEntityVariable("global_cooldown", "true");
        my $recovery_seconds = $recovery_time / 1000;
        $npc->SetTimer("global_cooldown_expire", $recovery_seconds);
    }
}

###########################################
## Spell Classification and Sorting
###########################################

sub get_sorted_beneficial_spells {
    my @all_spells = @_;
    my @beneficial = grep { quest::IsBeneficialSpell($_) } @all_spells;
    
    return sort {
        my $priority_a = get_beneficial_priority($a);
        my $priority_b = get_beneficial_priority($b);
        return $priority_a <=> $priority_b;
    } @beneficial;
}

sub get_sorted_harmful_spells {
    my @all_spells = @_;
    my @harmful = grep { !quest::IsBeneficialSpell($_) } @all_spells;
    
    return sort {
        my $priority_a = get_harmful_priority($a);
        my $priority_b = get_harmful_priority($b);
        return $priority_a <=> $priority_b;
    } @harmful;
}

# Helper function to get the effective spell level for prioritization
sub get_spell_level {
    my ($spell_id) = @_;
    my $spell = quest::getspell($spell_id);
    
    my $lowest_level = 255; # Start with max value
    
    # Check all 16 class slots
    for my $class_index (0..15) {
        my $level = $spell->GetClasses($class_index);
        
        # Skip levels 254 and 255 (class can't use the spell)
        if ($level < 254) {
            # Update lowest level if this one is lower
            if ($level < $lowest_level) {
                $lowest_level = $level;
            }
        }
    }
    
    # If lowest level is still 255, no class can use this spell
    if ($lowest_level == 255) {
        return 0; # Return 0 to indicate spell is not usable
    }
    
    return $lowest_level; # Return the lowest level any class can use this spell
}

sub get_beneficial_priority {
    my $spell_id = shift;
    my $spell = quest::getspell($spell_id);
    my $buff_duration = $spell->GetBuffDuration();
    
    # Get the lowest spell level
    my $spell_level = get_spell_level($spell_id);
    
    # If the spell is not usable by any class, give it lowest priority
    if ($spell_level == 0) {
        return 999;
    }
    
    # Base priority based on spell type
    my $base_priority;
    
    # Prioritize healing spells first
    if (quest::IsHealOverTimeSpell($spell_id) || quest::IsGroupHealOverTimeSpell($spell_id)) {
        $base_priority = 1; # Highest priority - HoTs
    }
    elsif (quest::IsRegularSingleTargetHealSpell($spell_id) || 
           quest::IsFastHealSpell($spell_id) || 
           quest::IsVeryFastHealSpell($spell_id) || 
           quest::IsCompleteHealSpell($spell_id) || 
           quest::IsPercentalHealSpell($spell_id)) {
        $base_priority = 2; # Second priority - Direct heals
    }
    # Then specifically approved buff types with higher priority
    elsif (quest::IsFullDeathSaveSpell($spell_id)) {
        $base_priority = 3; # Third priority - Death save buffs
    }
    elsif (quest::IsRuneSpell($spell_id) || quest::IsMagicRuneSpell($spell_id)) {
        $base_priority = 4; # Fourth priority - Protective runes
    }
    elsif (quest::IsHasteSpell($spell_id)) {
        $base_priority = 5; # Fifth priority - Haste buffs
    }
    # Then all other buffs
    elsif (quest::IsBuffSpell($spell_id)) {
        $base_priority = 10; # Lower priority - General buffs
    } else {
        # Any remaining beneficial spells not caught by the above
        $base_priority = 20; # Lowest usable priority
    }
    
    # For level adjustment, we want higher level spells to have better priority (lower number)
    # Since our priority system uses lower numbers for higher priority, we need to subtract
    # a value based on spell level to make higher level spells have better priority
    my $level_adjustment = $spell_level / 1000; 
    
    # Final priority = base priority minus level adjustment
    # This ensures higher level spells get slightly better priority within their category
    return $base_priority - $level_adjustment;
}

sub get_harmful_priority {
    my $spell_id = shift;
    
    # Get the lowest spell level
    my $spell_level = get_spell_level($spell_id);
    
    # If the spell is not usable by any class, give it lowest priority
    if ($spell_level == 0) {
        return 999;
    }
    
    # Base priority based on spell type
    my $base_priority;
    
    # Priority order (lower number = higher priority)
    if (quest::IsDebuffSpell($spell_id)) {
        # Prioritize debuffs first
        if (quest::IsResistDebuffSpell($spell_id)) {
            $base_priority = 1; # Highest priority - Resistance Debuffs
        } else {
            $base_priority = 2; # Second priority - Other Debuffs
        }
    } elsif (quest::IsStackableDOT($spell_id)) {
        $base_priority = 3; # Third priority - DOTs
    } elsif (quest::IsDamageSpell($spell_id)) {
        $base_priority = 4; # Fourth priority - Direct Damage
    } else {
        $base_priority = 99; # Lowest priority - Everything else
    }
    
    # For level adjustment, we want higher level spells to have better priority (lower number)
    # Since our priority system uses lower numbers for higher priority, we need to subtract
    # a value based on spell level to make higher level spells have better priority
    my $level_adjustment = $spell_level / 1000;
    
    # Final priority = base priority minus level adjustment
    # This ensures higher level spells get slightly better priority within their category
    return $base_priority - $level_adjustment;
}

###########################################
## Group and Pet Management
###########################################

# Function to get all pets owned by a character
sub get_all_pets {
    my $owner = shift;
    my @pets = ();
    
    foreach my $npc_e ($entity_list->GetNPCList()) {
        # Check if this NPC is owned by the specified owner
        if ($npc_e->GetOwnerID() == $owner->GetID()) {
            # Skip ourselves to avoid healing ourselves
            if ($npc_e->GetID() != $npc->GetID()) {
                push(@pets, $npc_e);
            }
        }
    }
    
    quest::debug("Found " . scalar(@pets) . " pets owned by " . $owner->GetName());
    return @pets;
}

# Function to get all group members and their pets
sub get_group_members_and_pets {
    my $owner = shift;
    my @targets = ();
    
    # Start with the owner
    push(@targets, $owner);
    
    # Add owner's pets
    my @owner_pets = get_all_pets($owner);
    push(@targets, @owner_pets);
    
    # Get the owner's group
    my $group = $entity_list->GetGroupByClient($owner);
    
    # If owner is in a group, add group members and their pets
    if ($group) {
        quest::debug("Owner is in a group with " . $group->GroupCount() . " members");
        
        # Loop through each group member
        for (my $count = 0; $count < $group->GroupCount(); $count++) {
            my $member = $group->GetMember($count);
            
            # Skip if member is the owner (already added)
            if ($member && $member->GetID() != $owner->GetID()) {
                quest::debug("Adding group member: " . $member->GetName());
                push(@targets, $member);
                
                # Add member's pets
                my @member_pets = get_all_pets($member);
                push(@targets, @member_pets);
            }
        }
    }
    
    quest::debug("Total targets (owner, group members, and all pets): " . scalar(@targets));
    return @targets;
}

# Function to prioritize healing targets based on their health
sub sort_targets_by_healing_priority {
    my @targets = @_;
    
    # Sort targets by health percentage (lower health = higher priority)
    my @sorted_targets = sort {
        my $hp_percent_a = ($a->GetHP() / $a->GetMaxHP()) * 100;
        my $hp_percent_b = ($b->GetHP() / $b->GetMaxHP()) * 100;
        
        # Primary sort by critical status (below 50% = critical)
        my $a_critical = ($hp_percent_a < 50) ? 1 : 0;
        my $b_critical = ($hp_percent_b < 50) ? 1 : 0;
        
        # Critical targets come first
        if ($b_critical != $a_critical) {
            return $b_critical <=> $a_critical;
        }
        
        # Then sort by lowest health percentage
        return $hp_percent_a <=> $hp_percent_b;
    } @targets;
    
    return @sorted_targets;
}

###########################################
## Spell Casting Helpers
###########################################

# Modified function to try casting beneficial spells on owner, group members, and pets
sub try_cast_beneficial_spell {
    my ($owner, @spell_list) = @_;
    
    # Get all potential healing/buffing targets (owner, group members, and all pets)
    my @all_targets = get_group_members_and_pets($owner);
    
    # First pass: Check for critical healing needs (below 50% HP)
    my @healing_targets = grep { 
        my $hp_percent = ($_->GetHP() / $_->GetMaxHP()) * 100;
        $hp_percent < 75; # Only consider targets below 75% HP for healing
    } @all_targets;
    
    # Sort healing targets by priority (most critical first)
    my @prioritized_healing_targets = sort_targets_by_healing_priority(@healing_targets);
    
    # Try to heal targets in priority order
    if (@prioritized_healing_targets) {
        quest::debug("Found " . scalar(@prioritized_healing_targets) . " targets needing healing");
        
        foreach my $target (@prioritized_healing_targets) {
            # Skip if target is self (this NPC)
            if ($target->GetID() == $npc->GetID()) {
                continue;
            }
            
            my $hp_percent = ($target->GetHP() / $target->GetMaxHP()) * 100;
            quest::debug("Considering healing " . $target->GetName() . " (HP: $hp_percent%)");
            
            if (try_heal_target($target, @spell_list)) {
                return 1; # Successfully healed a target
            }
        }
    }

	return 0;    
    # If no healing was needed or possible, try buffing targets
    # Buffing order: owner, group members, pets
    
    # Try buffing owner first
    quest::debug("Trying buff spells on owner");
    if (try_buff_target($owner, @spell_list)) {
        return 1; # Successfully buffed the owner
    }
    
    # Then try buffing group members (excluding owner)
    if ($entity_list->GetGroupByClient($owner)) {
        my $group = $entity_list->GetGroupByClient($owner);
        for (my $count = 0; $count < $group->GroupCount(); $count++) {
            my $member = $group->GetMember($count);
            
            # Skip if member is the owner (already tried)
            if ($member->GetID() != $owner->GetID()) {
                quest::debug("Trying buff spells on group member: " . $member->GetName());
                if (try_buff_target($member, @spell_list)) {
                    return 1; # Successfully buffed a group member
                }
            }
        }
    }
    
    # Finally try buffing all pets
    my @all_pets = grep { 
        $_->GetOwnerID() > 0 && $_->GetID() != $npc->GetID(); # Only include entities that have an owner and aren't self
    } @all_targets;
    
    foreach my $pet (@all_pets) {
        quest::debug("Trying buff spells on pet: " . $pet->GetName());
        if (try_buff_target($pet, @spell_list)) {
            return 1; # Successfully buffed a pet
        }
    }
    
    return 0; # No spell was cast
}

# Function to specifically handle healing a target
sub try_heal_target {
    my ($target, @spell_list) = @_;
    
    # Skip if target is self (this NPC)
    if ($target->GetID() == $npc->GetID()) {
        quest::debug("Skipping self (NPC) as heal target");
        return 0;
    }
    
    # Calculate target's HP percentage
    my $hp_percent = ($target->GetHP() / $target->GetMaxHP()) * 100;
    
    # Sort beneficial spells into healing categories
    my @heal_over_time_spells = grep { quest::IsHealOverTimeSpell($_) || quest::IsGroupHealOverTimeSpell($_) } @spell_list;
    my @direct_heal_spells = grep { 
        (quest::IsRegularSingleTargetHealSpell($_) || 
         quest::IsFastHealSpell($_) || 
         quest::IsVeryFastHealSpell($_) || 
         quest::IsCompleteHealSpell($_) || 
         quest::IsPercentalHealSpell($_)) && 
        !quest::IsHealOverTimeSpell($_)
    } @spell_list;
    
    # Debug logging
    quest::debug("Found " . scalar(@heal_over_time_spells) . " HoT spells and " . 
                 scalar(@direct_heal_spells) . " direct heal spells");
    
    # If below 50% HP, prioritize direct heals
    if ($hp_percent < 50) {
        quest::debug("Target is below 50% HP, trying direct healing spells");
        
        # Try to cast a direct heal
        foreach my $spell_id (@direct_heal_spells) {
            quest::debug("Trying direct heal spell $spell_id");
            if (try_cast_single_spell($target, $spell_id)) {
                return 1; # Spell was cast successfully
            }
        }
    }
    
    # Try heal over time spells
    if ($hp_percent < 75) {
        foreach my $spell_id (@heal_over_time_spells) {
            # For HoT spells, check if it's already on the target
            my $has_buff_result = has_buff($target, $spell_id);
            quest::debug("HoT spell $spell_id - Target already has this buff? " . 
                         ($has_buff_result ? "Yes" : "No"));
            
            if ($has_buff_result) {
                quest::debug("Target already has HoT spell $spell_id, skipping");
                next;
            }
            
            quest::debug("Trying HoT spell $spell_id");
            if (try_cast_single_spell($target, $spell_id)) {
                return 1; # Spell was cast successfully
            }
        }
    }
    
    return 0; # No healing spell was cast
}

# Function to specifically handle buffing a target
sub try_buff_target {
    my ($target, @spell_list) = @_;
    
    # Skip if target is self (this NPC)
    if ($target->GetID() == $npc->GetID()) {
        quest::debug("Skipping self (NPC) as a buff target");
        return 0;
    }
    
    # Extract all buff spells (not healing spells)
    my @buff_spells = grep { 
        quest::IsBeneficialSpell($_) && 
        !quest::IsHealOverTimeSpell($_) && 
        !quest::IsGroupHealOverTimeSpell($_) && 
        !quest::IsRegularSingleTargetHealSpell($_) && 
        !quest::IsFastHealSpell($_) && 
        !quest::IsVeryFastHealSpell($_) && 
        !quest::IsCompleteHealSpell($_) && 
        !quest::IsPercentalHealSpell($_)
    } @spell_list;
    
    # Sort buff spells by priority
    my @sorted_buff_spells = sort {
        my $priority_a = get_beneficial_priority($a);
        my $priority_b = get_beneficial_priority($b);
        return $priority_a <=> $priority_b;
    } @buff_spells;
    
    quest::debug("Found " . scalar(@sorted_buff_spells) . " buff spells to try");

	#not doing this yet
    
    # Categorize buffs for better logging
    my @death_save_buffs = grep { quest::IsFullDeathSaveSpell($_) } @sorted_buff_spells;
    my @rune_buffs = grep { quest::IsRuneSpell($_) || quest::IsMagicRuneSpell($_) } @sorted_buff_spells;
    my @haste_buffs = grep { quest::IsHasteSpell($_) } @sorted_buff_spells;
    my @other_buffs = grep { 
        !quest::IsFullDeathSaveSpell($_) && 
        !quest::IsRuneSpell($_) && 
        !quest::IsMagicRuneSpell($_) && 
        !quest::IsHasteSpell($_) &&
        quest::IsBuffSpell($_)
    } @sorted_buff_spells;
    
    quest::debug("Buff breakdown - Death Save: " . scalar(@death_save_buffs) . 
                 ", Runes: " . scalar(@rune_buffs) . 
                 ", Haste: " . scalar(@haste_buffs) . 
                 ", Other: " . scalar(@other_buffs));
    
    # Try each buff spell in priority order
    foreach my $spell_id (@sorted_buff_spells) {
        my $spell_type = "Other Buff";
        if (quest::IsFullDeathSaveSpell($spell_id)) {
            $spell_type = "Death Save";
        } elsif (quest::IsRuneSpell($spell_id) || quest::IsMagicRuneSpell($spell_id)) {
            $spell_type = "Rune";
        } elsif (quest::IsHasteSpell($spell_id)) {
            $spell_type = "Haste";
        }
        
        quest::debug("Trying $spell_type spell $spell_id");
        if (try_cast_single_spell($target, $spell_id)) {
            return 1; # Spell was cast successfully
        }
    }
    
    return 0; # No buff spell was cast
}

sub try_cast_harmful_spell {
    my ($target, @spell_list) = @_;
    
    # Skip if target is self (this NPC)
    if ($target->GetID() == $npc->GetID()) {
        quest::debug("Skipping self (NPC) as harmful spell target");
        return 0;
    }
    
    foreach my $spell_id (@spell_list) {
        # Skip spells that are on cooldown
        if ($npc->GetEntityVariable("recast_blocker_$spell_id") eq "true") {
            quest::debug("Harmful spell $spell_id is on cooldown, skipping");
            next;
        }
        
        my $spell = quest::getspell($spell_id);
        quest::debug("Checking harmful spell $spell_id on $target");
        
        # Check if the spell can be cast on the target
        my $can_cast = can_cast_harmful($target, $spell_id, $npc);
        
        if (!$can_cast) {
            quest::debug("Harmful spell $spell_id cannot be applied to target, skipping");
            next;
        }
        
        quest::debug("Casting harmful spell $spell_id on $target");
        $npc->CastSpell($spell_id, $target->GetID());
        return 1; # Indicate spell was cast
    }
    
    return 0; # No spell was cast
}

# Helper function to try casting a single spell
sub try_cast_single_spell {
    my ($target, $spell_id) = @_;
    
    # Skip if target is self (this NPC)
    if ($target->GetID() == $npc->GetID()) {
        quest::debug("Skipping spell cast on self (NPC)");
        return 0;
    }
    
    # Skip spells that are on cooldown
    if ($npc->GetEntityVariable("recast_blocker_$spell_id") eq "true") {
        quest::debug("Spell $spell_id is on cooldown, skipping");
        return 0;
    }
    
    my $spell = quest::getspell($spell_id);
    quest::debug("Checking spell $spell_id for target " . $target->GetName());
    
    # Check if the spell can be cast on the target
    my $can_cast = can_cast_beneficial($target, $spell_id, $npc);
    
    if (!$can_cast) {
        quest::debug("Spell $spell_id cannot be applied to target, skipping");
        return 0;
    }
    
    quest::debug("Casting spell $spell_id on target " . $target->GetName());
    $npc->CastSpell($spell_id, $target->GetID());
    return 1; # Indicate spell was cast
}

# Helper function with enhanced debugging to check if a target already has a specific buff
sub has_buff {
    my ($target, $spell_id) = @_;
    
    my @target_buffs = $target->GetBuffs();
    quest::debug("Checking for buff $spell_id on target " . $target->GetName() . 
                 ", found " . scalar(@target_buffs) . " buffs");
    
    # If no buffs found, return early
    if (scalar(@target_buffs) == 0) {
        quest::debug("Target has no buffs at all");
        return 0;
    }
    
    foreach my $buff (@target_buffs) {
        # Ensure buff object is valid
        if (!$buff) {
            quest::debug("Found a null buff object, skipping");
            next;
        }
        
        # Try-catch equivalent to handle potential errors
        eval {
            my $current_buff_id = $buff->GetSpellID();
            quest::debug("Comparing buff ID $current_buff_id with spell ID $spell_id");
            
            if ($current_buff_id == $spell_id) {
                quest::debug("Match found! Target has buff $spell_id");
                return 1; # Target has this buff
            }
        };
        
        if ($@) {
            quest::debug("Error checking buff: $@");
        }
    }
    
    quest::debug("Target does not have buff $spell_id");
    return 0; # Target doesn't have this buff
}

sub can_cast_beneficial {
    my ($target, $spell_id, $caster) = @_;
    
    # Get spell info
    my $spell = quest::getspell($spell_id);
    
    # Get buff duration - only apply stacking rules for spells with duration > 0
    my $buff_duration = $spell->GetBuffDuration();
    
    # If it's not a buff (duration <= 0), it's likely a heal, always allow casting
    if ($buff_duration <= 0) {
        quest::debug("Beneficial spell $spell_id is not a buff (duration = $buff_duration), can cast");
        return 1;
    }
    
    # First check: See if the exact spell already exists on the target
    my @target_buffs = $target->GetBuffs();
    foreach my $buff (@target_buffs) {
        # If it's the same spell ID
        if ($buff->GetSpellID() == $spell_id) {
            quest::debug("Beneficial spell $spell_id already exists on target");
            return 0;
        }
    }
    
    # Second check: Use CanBuffStack to see if the buff can be applied
    my $stack_result = $target->CanBuffStack($spell_id, $caster->GetLevel(), 1);
    quest::debug("CanBuffStack result for beneficial spell $spell_id: $stack_result");
    
    # Negative values indicate the buff cannot stack
    if ($stack_result < 0) {
        quest::debug("Beneficial spell $spell_id cannot stack on target (result: $stack_result)");
        return 0;
    }
    
    # If we made it here, the buff can be applied to the target
    quest::debug("Beneficial spell $spell_id can be cast on target");
    return 1;
}

sub can_cast_harmful {
    my ($target, $spell_id, $caster) = @_;
    
    # Get spell info
    my $spell = quest::getspell($spell_id);
    
    # Get buff duration - only apply stacking rules for spells with duration > 0
    my $buff_duration = $spell->GetBuffDuration();
    
    # If it's not a buff/debuff (duration <= 0), always allow casting
    if ($buff_duration <= 0) {
        quest::debug("Harmful spell $spell_id is not a buff (duration = $buff_duration), can cast");
        return 1;
    }
    
    # Check if it's a stackable DOT
    my $is_stackable_dot = quest::IsStackableDOT($spell_id);
    
    # Get all buffs on the target
    my @target_buffs = $target->GetBuffs();
    
    # Get caster name for comparison
    my $caster_name = $caster->GetCleanName();
    
    # First check: Look for the exact spell on the target
    foreach my $buff (@target_buffs) {
        # If it's the same spell ID
        if ($buff->GetSpellID() == $spell_id) {
            if ($is_stackable_dot) {
                # For stackable DOTs, check if WE already have one on the target
                quest::debug("Caster Compare: " . $buff->GetCasterName() . " vs " . $caster_name);
                if ($buff->GetCasterName() eq $caster_name) {
                    quest::debug("We already have this stackable DOT on the target, skipping");
                    return 0;
                }
                # If it's from another caster, continue with the stack check
            } else {
                # Non-stackable spell already exists on target, regardless of caster
                quest::debug("Non-stackable harmful spell already exists on target");
                return 0;
            }
        }
    }
    
    # Second check: Use CanBuffStack to see if the debuff can be applied
    my $stack_result = $target->CanBuffStack($spell_id, $caster->GetLevel(), 1);
    quest::debug("CanBuffStack result for harmful spell $spell_id: $stack_result");
    
    # Negative values indicate the debuff cannot stack
    if ($stack_result < 0) {
        quest::debug("Harmful spell $spell_id cannot stack on target (result: $stack_result)");
        return 0;
    }
    
    # If we made it here, either:
    # 1. The spell doesn't exist on the target, or
    # 2. It's a stackable DOT and we don't have our instance on the target yet
    # And the CanBuffStack check has passed
    quest::debug("Harmful spell $spell_id can be cast on target");
    return 1;
}