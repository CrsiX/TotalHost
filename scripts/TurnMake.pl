#!/usr/bin/perl
# TurnMake.pl
# Master Turn Generation Program for TotalHost
# Rick Steeves th@corwyn.net
# 120808, 121016

#     Copyright (C) 2012 Rick Steeves
# 
#     This file is part of TotalHost, a Stars! hosting utility.
#     TotalHost is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.

use Win32::ODBC;
require 'cgi-lib.pl';
use CGI qw(:standard);
#require ('timelocal.pl');
use Net::SMTP;
use TotalHost;
use StarStat;
do 'config.pl';

#use strict;
# Usable from the command line for a single game. Just give it the gamefile.
my $commandline = $ARGV[0];

# Get Time Information
($Second, $Minute, $Hour, $DayofMonth, $Month, $Year, $WeekDay, $WeekofMonth, $DayofYear, $IsDST, $CurrentDateSecs) = &GetTime; #So we have the time when we do the HTML
$CurrentEpoch = time();

# Open the database
$db = &DB_Open($dsn);

# Only load the holiday infromation once, so we can reuse it.
#@Holiday = &LoadHolidays($db); #Load the dates for the holidays

# If a single game is specified, process only that game
if ($commandline) {
  # Execute for a single GameFile
  $GameData = &LoadGamesInProgress($db,'SELECT * FROM Games WHERE ((GameFile=\'$GameFile\') AND (GameStatus=2 or GameStatus=3)) ORDER BY GameFile');
} else {
  # Check all Games
  $GameData = &LoadGamesInProgress($db,'SELECT * FROM Games WHERE GameStatus=2 or GameStatus = 3 ORDER BY GameFile');
}
my @GameData = @$GameData;
&CheckandUpdate;  
&DB_Close($db);

#####################################################################################

# Handy code reference for how variables work tho.
# sub Initialize { #Recreate all of the HTML pages for all of the games
# 	my $LoopPosition = 1;
# 	while ($LoopPosition <= $#GameData) { # For every game in progress
# 		print 'Initializing ' . $GameData[$LoopPosition]{'GameName'}. " Game\n";
# 		print "Values: Game Name: $GameData[$LoopPosition]{'GameName'}, Game File: $GameData[$LoopPosition]{'GameFile'}, Next Turn: $GameData[$LoopPosition]{'NextTurn'}, Status: $GameData[$LoopPosition]{'GameStatus'}\n";
# 		$LoopPosition++;
# 	}
# }

sub CheckandUpdate {
  # BUG: Doesn't this always skip the first game? ? ? 
	my $LoopPosition = 1; #Start with the first game in the array.
  print "Starting to check games\n";
  # This would be massively more clear if I read all of this in as a hash, instead
  # of an array. If I just moved $LoopPosition out, and instead performed this
  # as I walked thorugh the database. 
  # Heck, even if I read all the data in from the database, and then called this function one line/row
  # at a time. 
	while ($LoopPosition <= ($#GameData)) { # work the way through the array
		print 'Checking whether to generate for ' . $GameData[$LoopPosition]{'GameName'} . "...\n";
		my($TurnReady) = 'False'; #Is it time to generate
		my($NewTurn) = 0; #Localize the value for Next Turn. the next turn won't change unless told to
#		if ($GameData[$LoopPosition]{'ObserveHoliday'} ) { &CheckHolidays($GameData[$LoopPosition]{'NextTurn'}); }
		#check to see if you should be checking, and don't do anything at an invalid time. 
# 		if ((substr($GameData[$LoopPosition]{'DayFreq'},$WeekDay,1) == 0) && ($GameData[$LoopPosition]{'GameType'} == 1)) {
# 			print $WeekDay . " is not a good day\n"
# 		} elsif ((substr($GameData[$LoopPosition]{'HourFreq'},$Hour,1) == 0) && ($GameData[$LoopPosition]{'GameType'} == 2)) {
# 			print $WeekDay . " is not a good hour\n"
		#else {
		#	print $WeekDay . " is a good day\n";
		#}
		if (($GameData[$LoopPosition]{'GameStatus'} != 9) && (&inactive_game($GameData[$LoopPosition]{'GameFile'}))) {  # Don't bother checking if the game is no longer active. BUG: Shouldn't this be filtered out by SQL?
	   } elsif ($GameData[$LoopPosition]{'GameStatus'} == 2 || $GameData[$LoopPosition]{'GameStatus'} == 3) { # if it's an active game 		
	#Game Type = Daily
			if ($GameData[$LoopPosition]{'GameType'} == 1 && $CurrentEpoch > $GameData[$LoopPosition]{'NextTurn'}) { # GameType: turn set to daily
				&LogOut(200,"\t$GameData[$LoopPosition]{'GameName'} is a daily game $CurrentEpoch  $GameData[$LoopPosition]{'NextTurn'}",$LogFile);	
				# Generate the next turn = midnight today +  days + hours (fixed)
				# Which makes the time stay constant
				($DaysToAdd, $NextDayOfWeek) = &DaysToAdd($GameData[$LoopPosition]{'DayFreq'},$WeekDay);
				$NewTurn = $CurrentDateSecs + $DaysToAdd*86400 + ($GameData[$LoopPosition]{'DailyTime'} *60*60); 			
				# If the $newturn will be on an invalid day, add more days
				while (&ValidTurnTime($NewTurn,'Day',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { 
					# Get the weekday of the new turn so we can see if it's ok
					my ($CSecond, $CMinute, $CHour, $CDayofMonth, $CMonth, $CYear, $CWeekDay, $CDayofYear, $CIsDST) = localtime($NewTurn);
					# Move to the next available day
					($DaysToAdd, $NextDayOfWeek) = &DaysToAdd($GameData[$LoopPosition]{'DayFreq'},$CWeekDay);
#####
# Reset to the way it was 190314
#####
					$NewTurn = $NewTurn + &DaysToAdd($GameData[$LoopPosition]{'DayFreq'},$CWeekDay);
					$NewTurn = $NewTurn + $DaysToAdd * 86400;
				}
				# and just to be sure, make sure today is ok to generate before we approve everything
        # BUG: Why are we checking to confirm it's a valid day? What if we miss the valid day?  ? ?  
#				if (&ValidTurnTime($CurrentEpoch, 'Day', $GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) eq 'True') { $TurnReady = 'True'; }
				$TurnReady = 'True';
				&LogOut(100,"#####New Turn : $NewTurn  TurnReady = $TurnReady",$LogFile);
				# If there are any delays set, then we need to clear them out, and reset the game status
				# since if we're generating with a turn missing we've clearly hit the window past the delays.
				if ($GameData[$LoopPosition]{'DelayCount'} > 0) {
					$sql = "UPDATE Games SET DelayCount = 0 WHERE GameFile = \'$GameData[$LoopPosition]{'GameFile'}\';";
					if (&DB_Call($db,$sql)) { &LogOut(50, "Checkandupdate: Delay reset to 0 for $GameData[$LoopPosition]{'GameFile'}", $LogFile); }
					$sql = "UPDATE Games SET GameStatus = 2 WHERE GameFile = \'$GameData[$LoopPosition]{'GameFile'}\';";
					if (&DB_Call($db,$sql)) { &LogOut(50, "Checkandupdate: GameStatus reset to 2 for $GameData[$LoopPosition]{'GameFile'}", $LogFile); }
				}

	#Game Type = Hourly
			} elsif ($GameData[$LoopPosition]{'GameType'} == 2 && $CurrentEpoch > $GameData[$LoopPosition]{'NextTurn'}) { # GameType: set time to generate hourly
				print "   " . $GameData[$LoopPosition]{'GameName'} . " is an hourly game\n";
				# Generate the next turn now + number of hours (sliding)
				$NewTurn = $CurrentEpoch + ($GameData[$LoopPosition]{'HourlyTime'} *60 *60); 
				# Make sure we're generating on a valid day
				while (&ValidTurnTime($NewTurn,'Day',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { $NewTurn = $NewTurn + ($GameData[$LoopPosition]{'HourlyTime'} *60*60); }
				# Make sure we're generating on a valid hour
				while (&ValidTurnTime($NewTurn,'Hour',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { $NewTurn = $NewTurn + 3600; } 
				# and just to be sure, make sure today is ok to generate before we approve everything
				if (&ValidTurnTime($CurrentEpoch, 'Day',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) eq 'True') { $TurnReady = 'True'; } 
				&LogOut(100,"#####New Turn : $NewTurn  TurnReady = $TurnReady",$LogFile);

# BUG: This needs to reset delays? 

	#Game Type = All In
			} elsif ($GameData[$LoopPosition]{'GameType'} == 3) { #Turns only generated when all turns are in
				print $GameData[$LoopPosition]{'GameName'} . " is an All turns required game\n";
				$TurnReady = &Eval_CHK($GameData[$LoopPosition]{'GameFile'});
				if ($TurnReady eq 'True') { &LogOut(50,"   All turns are in for $GameData[$LoopPosition]{'GameName'}", $LogFile);	}
				else { &LogOut(100,"   All turns are not in for $GameData[$LoopPosition]{'GameName'}",$LogFile); }
	# Generate as Available
			} elsif ($GameData[$LoopPosition]{'AsAvailable'} == 1 && (!(&Turns_Missing($GameData[$LoopPosition]{'GameFile'})))) { # only check Generate As Available ongoing game status if necessary, if not, then return false
				$TurnReady = 'True';
				# If the game is in a delay state, don't increase the interval, and decrement the delay
				# if there's more than one delay
				if ($GameData[$LoopPosition]{'DelayCount'} > 1) {
					$sql = "UPDATE Games SET DelayCount = DelayCount -1 WHERE GameFile = \'$GameData[$LoopPosition]{'GameFile'}\';";
					if (&DB_Call($db,$sql)) { &LogOut(50, "Checkandupdate: Delay decremented for $GameData[$LoopPosition]{'GameFile'}", $LogFile); }
					$NewTurn = $GameData[$LoopPosition]{'NextTurn'};
				} else { 
					# If we're at the end of a delay we need to recalculate when the next turn is due
					if ($GameData[$LoopPosition]{'DelayCount'} == 1) {
						$sql = "UPDATE Games SET DelayCount = DelayCount -1 WHERE GameFile = \'$GameData[$LoopPosition]{'GameFile'}\';";
						if (&DB_Call($db,$sql)) { &LogOut(50, "Checkandupdate: Delay decremented for $GameData[$LoopPosition]{'GameFile'}", $LogFile); }
					}

					# Next turn is incremented by the correct # of days
					if ($GameData[$LoopPosition]{'GameType'} == 1) { #New Turn time = This turn time for today + X days
						# Determine when the next turn would normally be from right now. 
						($DaysToAdd, $NextDayOfWeek) = &DaysToAdd($GameData[$LoopPosition]{'DayFreq'},$WeekDay,$GameData[$LoopPosition]{'DailyTime'},$SecOfDay);
						my $NormalNextTurn = $CurrentDateSecs + ($DaysToAdd * 86400) + ($GameData[$LoopPosition]{'DailyTime'} *60*60); 			
						($DaysToAdd, $NextDayOfWeek) = &DaysToAdd($GameData[$LoopPosition]{'DayFreq'},$NextDayOfWeek);
						$NormalNextTurn = $NormalNextTurn + ($DaysToAdd * 86400);
						# Advance to the next valid day if $NormalNextTurn isn't on a valid day
						while (&ValidTurnTime($NormalNextTurn,'Day',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { 
							($CSecond, $CMinute, $CHour, $CDayofMonth, $CMonth, $CYear, $CWeekDay, $CDayofYear, $CIsDST, $CSecOfDay) = &CheckTime($NormalNextTurn);
							($DaysToAdd, $NextDayOfWeek) = &DaysToAdd($GameData[$LoopPosition]{'DayFreq'},$CWeekDay); 
							$NormalNextTurn = $NormalNextTurn + ($DaysToAdd * 86400); 
						}
						print "NormalNextTurn = " . localtime($NormalNextTurn) . "\n";

						# Determine when the next turn would be based on NextTurn
						# This is generating from NextTurn, so should only increment in days, not Days + hours like you
						# do when calculating from SecOfDay
						($CSecond, $CMinute, $CHour, $CDayofMonth, $CMonth, $CYear, $CWeekDay, $CDayofYear, $CIsDST, $CSecOfDay) = &CheckTime($GameData[$LoopPosition]{'NextTurn'});

						($DaysToAdd, $NextDayOfWeek) = &DaysToAdd($GameData[$LoopPosition]{'DayFreq'},$CWeekDay,$GameData[$LoopPosition]{'DailyTime'},$CSecOfDay);
						$NewTurn = $GameData[$LoopPosition]{'NextTurn'} + ($DaysToAdd * 86400); 
						print "1: New Turn = " . localtime($NewTurn) . " DaysToAdd = $DaysToAdd\n";
						# Advance to the next valid day if $NormalNextTurn isn't on a valid day
						while (&ValidTurnTime($NewTurn,'Day',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { 
							($CSecond, $CMinute, $CHour, $CDayofMonth, $CMonth, $CYear, $CWeekDay, $CDayofYear, $CIsDST, $CSecOfDay) = &CheckTime($NewTurn);
							($DaysToAdd, $NextDayOfWeek) = &DaysToAdd($GameData[$LoopPosition]{'DayFreq'},$CWeekDay); 
							$NewTurn = $NewTurn + ($DaysToAdd * 86400); 
						}
						print "2: New Turn Adjusted = " . localtime($NewTurn) . "\n";

						# If the turn based on NextTurn is more than the normal next turn date, then there's no need
						# to advance NextTurn; set the New Turn to not advance; instead stay the same.
						if ($NewTurn > $NormalNextTurn) {  
							&LogOut(200,"checkandupdate: $NewTurn > $NormalNextTurn",$LogFile); 
							# Don't increase the turn if it's already far enough in the future. 
 							$NewTurn = $GameData[$LoopPosition]{'NextTurn'};
							print "3: New Turn True = " . localtime($NewTurn) . "\n";
						} else {
							&LogOut(200,"checkandupdate: $NewTurn <= $NormalNextTurn",$LogFile); 
						}
					}
					# Next turn is generated Now + Game Interval
					if ($GameData[$LoopPosition]{'GameType'} == 2) { #
						# Determine when the next turn would normally be. 
						my $NormalNextTurn = $CurrentEpoch + (($GameData[$LoopPosition]{'HourlyTime'} *60 *60) * 2); 
						while (&ValidTurnTime($NormalNextTurn, 'Day',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { $NormalNextTurn = $NormalNextTurn + ($GameData[$LoopPosition]{'HourlyTime'}*60*60); }
						while (&ValidTurnTime($NormalNextTurn,'Hour',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { $NormalNextTurn = $NormalNextTurn + 3600; }
						$NewTurn = $CurrentEpoch + ($GameData[$LoopPosition]{'HourlyTime'}*60*60); 
						while (&ValidTurnTime($NewTurn, 'Day',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { $NewTurn = $NewTurn + ($GameData[$LoopPosition]{'HourlyTime'}*60*60); }
						while (&ValidTurnTime($NewTurn,'Hour',$GameData[$LoopPosition]{'DayFreq'}, $GameData[$LoopPosition]{'HourFreq'}) ne 'True') { $NewTurn = $NewTurn + 3600; }
						if ($NewTurn > $NormalNextTurn) {  
							&LogOut(200,"checkandupdate: $NewTurn > $NormalNextTurn",$LogFile); 
							# Don't increase the turn if it's already far enough in the future. 
							$NewTurn = $GameData[$LoopPosition]{'NextTurn'};
			}	}	}	}
	# If a turn is ready, generate it and process it through. 
			if ($TurnReady eq 'True') {
				&UpdateNextTurn($db,$NewTurn, $GameData[$LoopPosition]{'GameFile'}, $GameData[$LoopPosition]{'LastTurn'});		
				&UpdateLastTurn($db,time(), $GameData[$LoopPosition]{'GameFile'});		
				&LogOut(100,"Turn READY for $GameData[$LoopPosition]{'GameFile'}",$LogFile);
				my $HSTFile = $File_HST . '/' . $GameData[$LoopPosition]{'GameFile'} . '/' . $GameData[$LoopPosition]{'GameFile'} . '.hst';
				# Get the current turn and don't force generate on the first two turns, regardless. 
				($Magic, $lidGame, $ver, $HST_Turn, $iPlayer, $dt, $fDone, $fInUse, $fMulti, $fGameOver, $fShareware) = &starstat($HSTFile);
				# Check to see if it's a force gen game, and if so increase the number of times the game will generate unless first two turns
				my($NumberofTurns) = 1;
				if ($GameData[$LoopPosition]{'ForceGen'} == 1 && $HST_Turn ne '2400' && $HST_Turn ne '2401') {
					$NumberofTurns = $GameData[$LoopPosition]{'ForceGenTurns'};
					$NumberofTimes = $GameData[$LoopPosition]{'ForceGenTimes'} -1;
					# Update NumberofTimes
					$sql = "UPDATE Games SET ForceGenTimes = $NumberofTimes WHERE GameFile = \'$GameData[$LoopPosition]{'GameFile'}\'";
					if (&DB_Call($db,$sql)) { &LogOut(200,"Decremented ForceGenTimes for $GameData[$LoopPosition]{'GameFile'}",$LogFile); }
					else { &LogOut(200,"Failed to Decrement ForceGenTimes for $GameData[$LoopPosition]{'GameFile'}",$ErrorLog);}
					if ($NumberofTimes <= 0) { #If the game is no longer forced, unforce game
						$sql = "UPDATE Games SET ForceGen = 0 WHERE GameFile = \'$GameData[$LoopPosition]{'GameFile'}\'";
						if (&DB_Call($db,$sql)) { &LogOut(200,"Forcegen set to 0 for $GameData[$LoopPosition]{'GameFile'}",$LogFile) }
						else { &LogOut(0,"Failed to set forcegen to 0 for $GameData[$LoopPosition]{'GameFile'}",$ErrorLog); }
					}
				}
				&GenerateTurn($NumberofTurns, $GameData[$LoopPosition]{'GameFile'});
				# If Game was flagged as Delayed, once we generate it's not anymore
				if ($GameData[$LoopPosition]{'GameStatus'} == 3 && $GameData[$LoopPosition]{'DelayCount'} <= 0) { 
					$sql = "UPDATE Games SET GameStatus = 2 WHERE GameFile = \'$GameData[$LoopPosition]{'GameFile'}\'";
					if (&DB_Call($db,$sql)) { &LogOut(100, "TurnMake: Resetting Game Status for $GameData[$LoopPosition]{'GameFile'} to Active", $LogFile);  }
					else { &LogOut(0, "TurnMake: Failed to Reset Game Status for $GameData[$LoopPosition]{'GameFile'} to Active", $ErrorLog); }
				}
 
				# Update the .chk file so it's current for the new turn
        # Done in GenerateTurn
        # &Make_CHK($GameData[$LoopPosition]{'GameFile'});
#				sleep 2;  # And rest a moment so stars has time to think.
				my @CHK = &Read_CHK($GameData[$LoopPosition]{'GameFile'});

				# get the current turn so you can put it in the email, can vary based on force gen.
				($Magic, $lidGame, $ver, $HST_Turn, $iPlayer, $dt, $fDone, $fInUse, $fMulti, $fGameOver, $fShareware) = &starstat($HSTFile);
				$GameData[$LoopPosition]{'NextTurn'} = $NewTurn;
        
        # Decide whether to set player to inactive
        # Read in the game and player information from the CHK File
        # BUG: Not going to work quite right if the player is in the game more than once. 
    		my($InactivePosition) = 3;
        my $InactiveMessage = "";
        &LogOut(300, "STARTING AUTOINACTIVE", $LogFile);
        while (@CHK[$InactivePosition]) {  #read .m file lines
    			my ($CHK_Status, $CHK_Player) = &Eval_CHKLine(@CHK[$InactivePosition]);
    			my($Player) = $InactivePosition -2;
     			my $MFile = $File_HST . '/' . $GameData[$LoopPosition]{'GameFile'} . '/' . $GameData[$LoopPosition]{'GameFile'} . '.m' . $Player;
          &LogOut(300, ".m File: $MFile", $LogFile);
          # Get the Turn Year information for the player
    			($Magic, $lidGame, $ver, $turn, $iPlayer, $dt, $fDone, $fInUse, $fMulti, $fGameOver, $fShareware) = &starstat($MFile);
    			$TurnYears = $HST_Turn -$turn +1; 
          &LogOut(299, "Player: $Player Status: $CHK_Status  TurnYears: $TurnYears Player: $CHK_Player", $LogFile);
    			# Get the Player Status values for the current player
          $GameFile = $GameData[$LoopPosition]{'GameFile'};
    			$sql = qq|SELECT Games.GameFile, GameUsers.User_Login, GameUsers.PlayerID, GameUsers.PlayerStatus, [_PlayerStatus].PlayerStatus_txt FROM _PlayerStatus INNER JOIN ([User] INNER JOIN (Games INNER JOIN GameUsers ON (Games.GameFile = GameUsers.GameFile) AND (Games.GameFile = GameUsers.GameFile)) ON User.User_Login = GameUsers.User_Login) ON [_PlayerStatus].PlayerStatus = GameUsers.PlayerStatus WHERE (((Games.GameFile)=\'$GameFile\') AND ((GameUsers.PlayerID)=$Player));|;
    			if (&DB_Call($db,$sql)) { while ($db->FetchRow()) { %PlayerValues = $db->DataHash(); } }
    			# If the player is active, AND the number of turns missed is greater than AutoInactive, set the player to Inactive
          &LogOut(300, "Player Status: $PlayerValues{'PlayerStatus'}   AutoInactive: $GameData[$LoopPosition]{'AutoInactive'}  TurnYears: $TurnYears ", $LogFile); 
    			if (($PlayerValues{'PlayerStatus'} == 1) && ($GameData[$LoopPosition]{'AutoInactive'}) && ($TurnYears >= $GameData[$LoopPosition]{'AutoInactive'})) {
            &LogOut(300, "Need to set Player $Player to Inactive", $LogFile);  
            $sql = qq|UPDATE GameUsers SET PlayerStatus=2 WHERE PlayerID = $Player AND GameFile = '$GameFile';|;
            &LogOut(300, "SQL= $sql", $LogFile);
          	if (&DB_Call($db,$sql)) { 
              &LogOut(100,"Player $Player Status updated to Inactive for $GameFile having missed $TurnYears turns", $LogFile); 
              # Create the message for the email
              $InactiveMessage .= $InactiveMessage . "Player $Player Status changed to Inactive. No turns submitted for $TurnYears turn(s).\n";
            } else { &LogOut(0, "Player $Player Status failed to update to Inactive for $GameFile", $ErrorLog); }
          } else { }  # no need to do anything otherwise 
   			  undef %PlayerValues; # Need to clear array to be ready for the next player
    			$InactivePosition++;
    		}
        &LogOut(300, "ENDING AUTOINACTIVE", $LogFile);
       
				# Get the array into a format I can pass to the subroutine, which involves converting it to a direct hash.
				# If you're confused about why you use an '@' there on a hash slice instead of a '%', think of it like this. 
				# The type of bracket (square or curly) governs whether it's an array or a hash being looked at. 
				# On the other hand, the leading symbol ('$' or '@') on the array or hash indicates whether you are getting back 
				# a singular value (a scalar) or a plural one (a list).
				my $GameValues = $GameData[$LoopPosition];
				%GameValues = %$GameValues;
				$GameValues{'Message'} = "New turn available at $WWW_HomePage\n\n";
        # If any player(s) were set inactive, add that to the email notification
        $GameValues{'Message'} .= $InactiveMessage; 
				$GameValues{'HST_Turn'} = $HST_Turn;
				# Adjust the value of next turn in case there's DST
				# Since we've updated last turn, we need to use the original
				$GameValues{'NextTurn'} = &FixNextTurnDST($GameValues{'NextTurn'}, $GameData[$LoopPosition]{'LastTurn'},1);
        
				&Email_Turns($GameData[$LoopPosition]{'GameFile'}, \%GameValues, 1);
			}
			#Print when the next turn will be generated.
			if ($NewTurn) { print "1:Next turn for $GameData[$LoopPosition]{'GameFile'} gen on/after $NewTurn: " . localtime($NewTurn); }
			else { print "2:Next turn for $GameData[$LoopPosition]{'GameFile'} gen on/after $GameData[$LoopPosition]{'NextTurn'}: " . localtime($GameData[$LoopPosition]{'NextTurn'}); }
			if ($GameData[$LoopPosition]{'AsAvailable'} == 1) {	print ' or when all turns are in'; }		
			print ".\n";
		}
		$LoopPosition++;	#Now increment to check the next game
		# only process the first turn for debug purposes.
		# if ($debug) { die; }  # to make it only process the 1st record
  	}
	# Give the system a moment between each turn, Stars! is slow. 
	sleep 2;
}

# # Returns CSecofDay along with everything else
# sub CheckTime { #Determine information for a specified time in seconds of a day
# 	my($TimetoCheck) = @_;  # Pass in Epoch Time
# 	($CSecond, $CMinute, $CHour, $CDayofMonth, $CWrongMonth, $CWrongYear, $CWeekDay, $CDayofYear, $CIsDST) = localtime($TimetoCheck); 
# 	$CMonth = $CWrongMonth + 1; 
# 	$CYear = $CWrongYear + 1900;
# 	$CSecOfDay = ($CMinute * 60) + ($CHour*60*60) + $CSecond;
# 	return ($CSecond, $CMinute, $CHour, $CDayofMonth, $CMonth, $CYear, $CWeekDay, $CDayofYear, $CIsDST, $CSecOfDay);
# }

# In th.pm sorta
# sub ValidTurnTime { #Determine whether submitted time is valid to generate a turn
#   # BUG: (remarked out functon): $loopposition is used to determine array location 
#   # That's the real difference between this and the &ValidTurnTime in TurnMake
#   # Better to just pass the relevant array values and merge the two functions
# 	my($ValidTurnTimeTest, $WhentoTestFor, $LoopPosition) = @_;	
# 	my($ValidTurnTimeTest, $WhentoTestFor, $Day, $Hour) = @_;	
#   
# 	&LogOut(100,"ValidTurnTimeTest: $ValidTurnTimeTest, WhentoTestfor: $WhentoTestFor",$LogFile);
# 	my($Valid) = 'True';
# 	#Check to see if it's a holiday
# # 	if ($GameData[$LoopPosition]{'ObserveHoliday'}){ 
# # 			local($Holiday) = &CheckHolidays($ValidTurnTimeTest,$db);  #BUG: How are we passing $db here? We don't have it.
# # 			if ($Holiday eq 'True') { $Valid = 'False'; }
# # 	}
# 	my ($CSecond, $CMinute, $CHour, $CDayofMonth, $CMonth, $CYear, $CWeekDay, $CDayofYear, $CIsDST, $CSecOfDay) = &CheckTime($ValidTurnTimeTest);
# 	#Check to see if it's a valid Day
# #	my($DayFreq) = &ValidFreq($GameData[$LoopPosition]{'DayFreq'},$CWeekDay);
# 	my($DayFreq) = &ValidFreq($Day,$CWeekDay);
# 	if ($DayFreq eq 'False') { $Valid = 'False'; }
# 	#Check to see if it's a valid hour
# 	if (($WhentoTestFor) eq 'Hour') {
# #		my($HourlyTime) = &ValidFreq($GameData[$LoopPosition]{'HourFreq'},$CHour);
# 		my($HourlyTime) = &ValidFreq($Hour,$CHour);
# 		if ($HourlyTime eq 'False') { $Valid = 'False'; }
# 	}
# 	&LogOut(200,"   Valid = $Valid ",$LogFile);
# 	return($Valid);
# }

# Check to see if all the turns are in taking everything into account
# Stars reported status, host-defined player status
sub Turns_Missing {
	my ($GameFile) = @_;
	my $TurnsMissing = 0;
	my @Status, @CHK;
	my %Values;
#   my($CheckGame) = $executable . 'stars.exe -v ' . $FileHST . '\\' . $GameFile . '\\' . $GameFile . '.hst';
 	my $CHKFile = $FileHST . '\\' . $GameFile . '\\' . $GameFile . '.chk';
# 	# Determine the number of players in the CHK file
# 	&LogOut(200,"Create CHK $CheckGame",$LogFile);
#   	system($CheckGame);
# 	sleep 2; 
# 	&LogOut(200,"Create CHK $CheckGame Complete",$LogFile);
  &Make_CHK($GameFile);
	# Determine the number of players in the CHK File
	if (-e $CHKFile) { #Check to see if .chk file is there.
		&LogOut(200,"Reading CHK File $CHKFile",$LogFile);
		open (IN_CHK,$CHKFile) || &LogOut(0,"Cannot open .chk file $CHKFile", $ErrorLog);
		chomp((@CHK) = <IN_CHK>);
	 	close(IN_CHK);
		for (my $i=3; $i <= @CHK - 1; $i++) { # Skip over starting lines
			my $id = $i - 2;
			$Status[$id] = @CHK[$i];
		}
	} else { &LogOut(0,'Cannot open .chk file - die die die ',$ErrorLog); die; }
	# Run through all the players in the database and check status	
	$sql = qq|SELECT GameUsers.PlayerID, GameUsers.PlayerStatus FROM Games INNER JOIN GameUsers ON Games.GameFile = GameUsers.GameFile WHERE GameUsers.GameFile = '$GameFile' AND GameUsers.PlayerStatus=1;|;
	if (&DB_Call($db,$sql)) { 
		while ($db->FetchRow()) { 
			%Values = $db->DataHash(); 
			if ((index($Status[$Values{'PlayerID'}], 'turned in') == -1) && (index($Status[$Values{'PlayerID'}], 'dead') == -1)) { &LogOut(300,"OUT $Values{'PlayerID'}: $Status[$Values{'PlayerID'}]",$LogFile); $TurnsMissing = 1; }
			else { &LogOut(300,"IN $Values{'PlayerID'}: $Status[$Values{'PlayerID'}]",$LogFile);  }
		} 
	}
	if ($TurnsMissing) { &LogOut(200,".x files are missing for $GameFile",$LogFile) } else { &LogOut(200,"All .x files are in for $GameFile",$LogFile); }
	return $TurnsMissing;
}

sub inactive_game {
	my ($GameFile) = @_;
	# Determine when the last game turn was submitted
	my $UserCounter = 0;
	my $sql = qq|SELECT * FROM GameUsers WHERE GameFile = \'$GameFile\';|;
	my %UserValues;
	my $LastSubmitted = -1;

	my $db = &DB_Open($dsn);
	# Read in all the user data for the game.
	if (&DB_Call($db,$sql)) { 	while ($db->FetchRow()) { 
		my %UserValues = $db->DataHash(); 
		$UserCounter++;
		@UserData[$UserCounter] = { %UserValues };
		# Get the largest/ most recent Last Generated value
		if ($UserData[$UserCounter]{'LastSubmitted'} > $LastSubmitted ) { $LastSubmitted = $UserData[$UserCounter]{'LastSubmitted'}; }
	} }
	#while ( my ($key, $value) = each(%UserValues) ) { print "$key => $value\n"; }

	my $currenttime = time();
	# Check to see if it's been too long since a turn was generated
	# Can't use .x[n] file date because it gets removed when turns gen.
  # BUG: If no one has ever submitted a turn, don't deactivate game
	if ((($currenttime - $LastSubmitted) > ($max_inactivity * 86400)) && ($LastSubmitted > 0)) {
		my $log = "$GameFile Inactive, last submitted on " . localtime($LastSubmitted); 
		&LogOut(50,$log, $ErrorLog);
		# End/Pause the game
		$sql = qq|UPDATE Games SET GameStatus = 4 WHERE GameFile = \'$GameFile\'|;
		if (&DB_Call($db,$sql)) {
			&LogOut(100, "$GameFile Ended/Paused for lack of activity", $LogFile);
		} else {
			&LogOut(0, "$GameFile Failed to end for lack of activity", $ErrorFile);
		}
		return 1; 
	} else { return 0; }
	&DB_Close($db); 
}
