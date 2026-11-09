--------------------------- MODULE WritingFlow ---------------------------
EXTENDS Integers, FiniteSets, TLC
CONSTANTS Surfaces, Duration, Silence, Times, RootRule
VARIABLES surface, credential, used, phase, now, started, last, text,
          hint, hintCount, armed, expected, event, receipt, charged
vars == <<surface, credential, used, phase, now, started, last, text,
          hint, hintCount, armed, expected, event, receipt, charged>>
Live == phase \in {"writing", "warn"}
Access == surface # "Mac" \/ credential = "valid" \/
          (credential = "fresh" /\ used < 3)
Finish == started + Duration
Limit == IF surface = "Mac" THEN Silence ELSE 8
WarnAt == Limit - 3
Wipe == last + Limit
LegacyRoot == surface = "Root" /\ RootRule = "prefix"
Decision(t) == IF started = -1 THEN "live"
               ELSE IF t >= Wipe /\ Wipe <= Finish THEN "wipe"
               ELSE IF t >= Finish THEN "keep" ELSE "live"
Init == /\ surface \in Surfaces
        /\ credential \in {"fresh", "valid", "residue"}
        /\ used \in {0, 2, 3}
        /\ (surface # "Mac" => credential = "fresh" /\ used = 0)
        /\ phase = "home" /\ now = 0 /\ started = -1 /\ last = -1
        /\ text = {} /\ hint = FALSE /\ hintCount = 0 /\ armed = -1
        /\ expected = "none" /\ event = "init" /\ receipt = -1 /\ charged = FALSE
Enter == /\ phase = "home"
         /\ phase' = IF Access THEN "empty" ELSE "locked"
         /\ event' = "enter" /\ expected' = "none"
         /\ UNCHANGED <<surface, credential, used, now, started, last, text,
                        hint, hintCount, armed, receipt, charged>>
FirstInput == /\ phase = "empty" /\ started = -1
              /\ phase' = "writing" /\ started' = 0 /\ last' = 0 /\ now' = 0
              /\ text' = {"old"} /\ event' = "first" /\ expected' = "live"
              /\ charged' = (surface = "Mac" /\ credential = "fresh")
              /\ used' = IF charged' THEN used + 1 ELSE used
              /\ armed' = -1
              /\ UNCHANGED <<surface, credential, hint, hintCount, receipt>>
Max0(n) == IF n < 0 THEN 0 ELSE n
InputAt(t) == /\ Live /\ t \in Times /\ t >= now
              /\ expected' = Decision(t) /\ event' = "input" /\ now' = t
              /\ IF Decision(t) = "live" \/ LegacyRoot
                 THEN /\ phase' = "writing" /\ last' = t /\ text' = text \cup {"new"}
                      /\ UNCHANGED <<started, used, charged, receipt>>
                 ELSE IF Decision(t) = "keep"
                      THEN /\ phase' = "kept" /\ UNCHANGED <<last, text, started, used, charged, receipt>>
                      ELSE /\ text' = IF Access THEN {"new"} ELSE {}
                           /\ phase' = IF Access THEN "restarted" ELSE "locked"
                           /\ used' = IF surface = "Mac" /\ credential = "fresh" /\ Access THEN used + 1 ELSE used
                           /\ charged' = FALSE
                           /\ receipt' = Max0(Finish - Wipe)
                           /\ UNCHANGED <<started, last>>
              /\ armed' = -1 /\ hint' = IF Decision(t) = "live" THEN hint ELSE FALSE
              /\ UNCHANGED <<surface, credential, hintCount>>
TickAt(t) == /\ Live /\ t \in Times /\ t >= now
             /\ expected' = Decision(t) /\ event' = "tick" /\ now' = t
             /\ phase' = CASE Decision(t) = "wipe" -> "wiped"
                              [] Decision(t) = "keep" -> "kept"
                              [] started # -1 /\ t - last >= WarnAt -> "warn"
                              [] OTHER -> "writing"
             /\ text' = IF Decision(t) = "wipe" THEN {} ELSE text
             /\ receipt' = IF Decision(t) = "wipe"
                            THEN IF LegacyRoot THEN Max0(Duration - (t-started))
                                 ELSE Max0(Finish-Wipe)
                            ELSE receipt
             /\ hint' = IF phase' # "writing" THEN FALSE ELSE hint
             /\ UNCHANGED <<surface, credential, used, started, last, hintCount, armed, charged>>
Delete == /\ phase \in {"empty", "writing", "warn", "wiped"}
          /\ event' = "delete" /\ expected' = "none"
          /\ hint' = IF surface # "Root" /\ phase \in {"empty", "writing"} /\ hintCount = 0 THEN TRUE ELSE hint
          /\ hintCount' = IF hint' THEN 1 ELSE hintCount
          /\ UNCHANGED <<surface, credential, used, phase, now, started, last, text, armed, receipt, charged>>
Escape == /\ phase \in {"empty", "writing", "warn", "wiped", "kept"}
          /\ event' = "escape" /\ expected' = IF armed # -1 /\ now - armed <= 2 THEN "secondExit" ELSE "firstExit"
          /\ IF surface = "Root" \/ (armed # -1 /\ now - armed <= 2)
             THEN /\ phase' = "left" /\ text' = {} /\ armed' = -1 /\ hint' = FALSE
             ELSE /\ armed' = now /\ UNCHANGED <<phase, text, hint>>
          /\ UNCHANGED <<surface, credential, used, now, started, last, hintCount, receipt, charged>>
ExpireExit == /\ armed # -1
              /\ \E t \in Times: t >= now /\ t - armed > 2 /\ now' = t
              /\ armed' = -1 /\ event' = "expire" /\ expected' = "none"
              /\ UNCHANGED <<surface, credential, used, phase, started, last, text, hint, hintCount, receipt, charged>>
Restart == /\ phase = "wiped"
           /\ phase' = IF Access THEN "restarted" ELSE "locked"
           /\ event' = "restart" /\ expected' = "none" /\ hint' = FALSE /\ hintCount' = 0
           /\ UNCHANGED <<surface, credential, used, now, started, last, text, armed, receipt, charged>>
BeginAgain == /\ phase = "kept"
              /\ phase' = IF Access THEN "empty" ELSE "locked"
              /\ text' = {} /\ started' = -1 /\ last' = -1 /\ charged' = FALSE
              /\ event' = "again" /\ expected' = "none" /\ hint' = FALSE /\ hintCount' = 0
              /\ armed' = -1
              /\ UNCHANGED <<surface, credential, used, now, receipt>>
Done == /\ phase \in {"left", "locked", "restarted"}
        /\ UNCHANGED vars
Next == Enter \/ FirstInput \/ (\E t \in Times: InputAt(t)) \/
        (\E t \in Times: TickAt(t)) \/ Delete \/ Escape \/ ExpireExit \/ Restart \/ BeginAgain \/ Done
Spec == Init /\ [][Next]_vars

NoLateRescue == event = "input" /\ expected = "wipe" => "old" \notin text
DeadlineBeforeInput == event = "input" /\ expected = "keep" => phase = "kept"
EarlierDeadlineWins == event = "tick" /\ expected = "keep" => phase = "kept"
TieAndSilenceDelete == event = "tick" /\ expected = "wipe" => phase = "wiped" /\ text = {}
DeadlineReceipt == event \in {"tick", "input"} /\ expected = "wipe" => receipt = Max0(Finish-Wipe)
OnlyAuthorizedEntry == phase \in {"empty", "writing", "warn"} /\ surface = "Mac" =>
                        credential = "valid" \/ (credential = "fresh" /\ (used < 3 \/ charged))
TrialBound == used <= 3
FirstInputCharges == event = "first" /\ surface = "Mac" /\ credential = "fresh" => charged
LicenseIndependentOfTrial == phase = "locked" /\ event = "enter" =>
                             surface = "Mac" /\ credential # "valid"
NoticeOnce == hintCount \in {0,1}
WarningOwnsNote == phase \in {"warn", "wiped", "kept", "left", "locked", "restarted"} => ~hint
ExitClearsText == phase = "left" => text = {}
InputCancelsExit == event \in {"first", "input"} => armed = -1
NoEmptyKept == phase = "kept" => text # {}
ClockWaitsForFirst == phase = "empty" => started = -1
DeletionNeverErasesCommitted == event = "delete" /\ Live => "old" \in text
TwoActExit == phase = "left" /\ surface # "Root" => expected = "secondExit"
=============================================================================
