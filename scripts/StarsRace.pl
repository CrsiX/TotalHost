# StarsRace.pl
#
# Rick Steeves
# starsah@corwyn.net
# Version History
# 180815  Version 1.0
# 191123 Version 1.1 mostly working to display all race info
#
#     Copyright (C) 2019 Rick Steeves
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
#

#
# Gets Race attributes
# Example Usage: StarsRace.pl c:\stars\game.m1
#
# Gets the values from a Race File
# Note that the race file has a checksum value, so writing out changes will 
# fail.
#
# Derived from decryptor.py and decryptor.java from
# https://github.com/stars-4x/starsapi  
#
# This is integrated into TotalHost StarsBlock. Don't get them out of sync.

use strict;
use warnings;   
use File::Basename;  # Used to get filename components
use StarsBlock; # A Perl Module from TotalHost
my $debug = 1;

my @singularRaceName;
my @pluralRaceName;

#Stars random number generator class used for encryption
my @primes = ( 
                3, 5, 7, 11, 13, 17, 19, 23, 
                29, 31, 37, 41, 43, 47, 53, 59,
                61, 67, 71, 73, 79, 83, 89, 97,
                101, 103, 107, 109, 113, 127, 131, 137,
                139, 149, 151, 157, 163, 167, 173, 179,
                181, 191, 193, 197, 199, 211, 223, 227,
                229, 233, 239, 241, 251, 257, 263, 279,
                271, 277, 281, 283, 293, 307, 311, 313 
        );
        
my $filename = $ARGV[0]; # input file
if (!($filename)) { 
  print "\n\nUsage: StarsRace.pl <input file>\n\n";
  print "Please enter the input file (.R|.M|.HST). Example: \n";
  print "  StarsRace.pl c:\\games\\test.r1\n\n";
  print "\nAs always when using any tool, it's a good idea to back up your file(s).\n";
  exit;
}
# Validate that the file exists
unless (-e $ARGV[0]) { print "File: $filename does not exist!\n"; exit; }

my ($basefile, $dir, $ext);
# for c:\stars\mygamename.m1
$basefile = basename($filename);    # mygamename.m1
$dir  = dirname($filename);         # c:\stars
($ext) = $basefile =~ /(\.[^.]+)$/; # .m1

# Read in the binary Stars! file, byte by byte
my $FileValues;
my @fileBytes;
open(StarFile, "<$filename");
binmode(StarFile);
while (read(StarFile, $FileValues, 1)) {
  push @fileBytes, $FileValues; 
}
close(StarFile);

# Decrypt the data, block by block
my ($outBytes) = &decryptBlockRace(@fileBytes);
my @outBytes = @{$outBytes};


################################################################
sub decryptBlockRace {
  my (@fileBytes) = @_;
  my @block;
  my @data;
  my ($decryptedData, $encryptedBlock, $padding);
  my @decryptedData;
  my @encryptedBlock;
  my @outBytes;
  my ( $binSeed, $fShareware, $Player, $turn, $lidGame, $Magic);
  my ( $random, $seedA, $seedB, $seedX, $seedY);
  my ($typeId, $size, $data);
  my $offset = 0; #Start at the beginning of the file
  while ($offset < @fileBytes) {
    # Get block info and data
    ($typeId, $size, $data) = &parseBlock(\@fileBytes, $offset);
    @data = @{ $data }; # The non-header portion of the block
    @block =  @fileBytes[$offset .. $offset+(2+$size)-1]; # The entire block in question
    if ($debug > 1) { print "\nBLOCK typeId: $typeId, Offset: $offset, Size: $size\n"; }
    if ($debug > 1) { print "BLOCK RAW: Size " . @block . ":\n" . join ("", @block), "\n"; }
    # FileHeaderBlock, never encrypted
    if ($typeId == 8) {
      # We always have this data before getting to block 6, because block 8 is first
      # If there are two (or more) block 8s, the seeds reset for each block 8
      ( $binSeed, $fShareware, $Player, $turn, $lidGame, $Magic) = &getFileHeaderBlock(\@block);
      ( $seedA, $seedB) = &initDecryption ($binSeed, $fShareware, $Player, $turn, $lidGame);
      $seedX = $seedA; # Used to reverse the decryption
      $seedY = $seedB; # Used to reverse the decryption
      push @outBytes, @block;
     } elsif ($typeId == 7) {
      # Note that planet's data requires something extra to decrypt. 
      # Fortunately block 7 isn't in my test files
      die "BLOCK 7 found. ERROR!\n";
    } else {
      # Everything else needs to be decrypted
      ($decryptedData, $seedA, $seedB, $padding) = &decryptBytes(\@data, $seedA, $seedB); 
      @decryptedData = @{ $decryptedData };
      # WHERE THE MAGIC HAPPENS
      if ($typeId == 6) { # Player Block
        if ($debug) { print "\nBLOCK typeId: $typeId, Offset: $offset, Size: $size\n"; }
        if ($debug) { print "DATA DECRYPTED:" . join (" ", @decryptedData), "\n"; }
        my $playerId = $decryptedData[0] & 0xFF; print "Player Id: $playerId\n";
        my $shipDesigns = $decryptedData[1] & 0xFF;  print " Ship Designs: $shipDesigns\n";
        my $planets = ($decryptedData[2] & 0xFF) + (($decryptedData[3] & 0x03) << 8); print " Planets: $planets\n";
        my $fleets = ($decryptedData[4] & 0xFF) + (($decryptedData[5] & 0x03) << 8);  print " Fleets: $fleets\n";
        my $starbaseDesigns = (($decryptedData[5] & 0xF0) >> 4); print " Starbase Designs: $starbaseDesigns\n";
        my $logo = (($decryptedData[6] & 0xFF) >> 3); print " Logo: $logo\n";
        my $fullDataFlag = ($decryptedData[6] & 0x04); print "fullDataFlag: $fullDataFlag\n";
        # We figure out names here, because they're here at 8 when not fullDataFlag 
        my $index = 8; 
        my $playerRelations;
        if ($fullDataFlag) { 
          # The player names are at the end and are not a fixed length,
          # The number of player relations bytes change where the names start   
          # That also changes whether it's a fullData set or not. 
          $index = 112;
          my $playerRelationsLength = $decryptedData[112]; 
          $index = $index + $playerRelationsLength + 1;
        }  
        my $singularNameLength = $decryptedData[$index] & 0xFF;
        my $singularMessageEnd = $index + $singularNameLength;
        my $pluralNameLength = $decryptedData[$index+2] & 0xFF;
        $singularRaceName[$playerId] = &decodeBytesForStarsString(@decryptedData[$index..$singularMessageEnd]);
        $pluralRaceName[$playerId] = &decodeBytesForStarsString(@decryptedData[$singularMessageEnd+1..$size-1]);
        print "playerName $playerId: $singularRaceName[$playerId]:$pluralRaceName[$playerId]\n";  
        
        if ($fullDataFlag) { 
          my $homeWorld = &read16(\@decryptedData, 8);
          print "Homeworld: $homeWorld\n";
          # BUG: the references say this is two bytes, but I don't think it is.
          # That means I don't know what byte 11 is tho. 
         my $rank = $decryptedData[10];
          print "Player Rank: $rank\n";
          # Bytes 12..15 are the password;
          my $centreGravity = $decryptedData[16]; # (base 65), 255 if immune 
          my $centreTemperature = $decryptedData[17]; #(base 35), 255 if immune  
          my $centreRadiation = $decryptedData[18]; # , 255 if immune 
          my $lowGravity      = $decryptedData[19];
          my $lowTemperature  = $decryptedData[20];
          my $lowRadiation    = $decryptedData[21];
          my $highGravity     = $decryptedData[22];
          my $highTemperature = $decryptedData[23];
          my $highRadiation   = $decryptedData[24];
          my $growthRate      = $decryptedData[25];
          print "Grav: " . &showHab($lowGravity,$centreGravity,$highGravity) . ", Temp: " . &showHab($lowTemperature,$centreTemperature,$highTemperature) . ", Rad: " . &showHab($lowRadiation,$centreRadiation,$highRadiation) . ", Growth: $growthRate\%\n"; 
                    # Worth noting all of these are +18 when in the fullDataFlag
          my $energyLevel           = $decryptedData[26];
          my $weaponsLevel          = $decryptedData[27];
          my $propulsionLevel       = $decryptedData[28];
          my $constructionLevel     = $decryptedData[29];
          my $electronicsLevel      = $decryptedData[30];
          my $biotechLevel          = $decryptedData[31];
          print "Tech Level: $energyLevel, $weaponsLevel, $propulsionLevel, $constructionLevel, $electronicsLevel, $biotechLevel\n";    
          my $energyLevelPointsSincePrevLevel         = $decryptedData[32]; # (4 bytes) 
          my $weaponsLevelPointsSincePrevLevel        = $decryptedData[36]; # (4 bytes) 
          my $propulsionLevelPointsSincePrevLevel     = $decryptedData[42]; # (4 bytes) 
          my $constructionLevelPointsSincePrevLevel   = $decryptedData[46]; # (4 bytes) 
          my $electronicsLevelPointsSincePrevLevel     = $decryptedData[50]; # (4 bytes)
          my $biologyLevelPointsSincePrevLevel         = $decryptedData[54]; # (4 bytes)
          print "Tech Points: $energyLevelPointsSincePrevLevel, $weaponsLevelPointsSincePrevLevel, $propulsionLevelPointsSincePrevLevel, $constructionLevelPointsSincePrevLevel, $electronicsLevelPointsSincePrevLevel, $biologyLevelPointsSincePrevLevel \n";
          my $researchPercentage    = $decryptedData[56];
          print "Research Percentage: $researchPercentage\n";
          my $currentResourcePriority = $decryptedData[57] >> 4; # (right 4 bits) [same, energy ..., lowest]
          print "Research Priority: " . &showResearchPriority($currentResourcePriority) . "\n";
          my $nextResourcePriority  = $decryptedData[57] & 0x04; # (left 4 bits)
          print "Next Priority: " . &showResearchPriority($nextResourcePriority) . "\n";
          my $researchPointsPreviousYear = $decryptedData[58]; # (4 bytes)
          print "researchPointsPreviousYear: $researchPointsPreviousYear\n";
          my $resourcePerColonist = $decryptedData[62]; # ? 55? 
          my $producePerFactory = $decryptedData[63];
          my $toBuildFactory = $decryptedData[64];
          my $operateFactory = $decryptedData[65];
          my $producePerMine = $decryptedData[66];
          my $toBuildMine = $decryptedData[67];
          my $operateMine = $decryptedData[68];
          print "Productivity: Colonist: $resourcePerColonist, Factory: $producePerFactory, $toBuildFactory, $operateFactory, Mine: $producePerMine, $toBuildMine, $operateMine\n";
          my $spendLeftoverPoints = $decryptedData[69]; # ?  (3:factories) 
          print "Leftover Points: " . &showLeftoverPoints($spendLeftoverPoints) . "\n";; 
          my $researchEnergy        = $decryptedData[70]; # (0:+75%, 1: 0%, 2:-50%) 
          my $researchWeapons       = $decryptedData[71]; # (0:+75%, 1: 0%, 2:-50%)
          my $researchProp          = $decryptedData[72]; # (0:+75%, 1: 0%, 2:-50%)
          my $researchConstruction  = $decryptedData[73]; # (0:+75%, 1: 0%, 2:-50%)
          my $researchElectronics   = $decryptedData[74]; # (0:+75%, 1: 0%, 2:-50%)
          my $researchBiotech       = $decryptedData[75]; # (0:+75%, 1: 0%, 2:-50%)
          print "Research Cost:  " . &showResearchCost($researchEnergy) . ", " . &showResearchCost($researchWeapons) . ", " . &showResearchCost($researchProp). ", " . &showResearchCost($researchConstruction) . ", " . &showResearchCost($researchElectronics) . ", " . &showResearchCost($researchBiotech) . "\n";
          my $PRT = $decryptedData[76]; # HE SS WM CA IS SD PP IT AR JOAT  
          print "PRT: " . &showPRT($PRT) . "\n";
          #$decryptedData[77]; unknown , always 0
          my $LRT =  $decryptedData[78]  + ($decryptedData[79] * 0x100); 
          my @LRTs = &showLRT($LRT);
          print "LRTs: " . join(',',@LRTs) . "\n";
          my $checkBoxes = $decryptedData[81]; 
            #<Unknown bits="5"/> 
            my $expensiveTechStartsAt3 = &bitTest($checkBoxes, 5);
            # Unknown bit 6
            my $factoriesCost1LessGerm = &bitTest($checkBoxes, 7);
          print "Expensive Tech Starts at 3: " . &showExpensiveTechStartsAt3($expensiveTechStartsAt3) . "\n";
          print "FactoriesCost1LessGerm: " . &showFactoriesCost1LessGerm($factoriesCost1LessGerm) . "\n";
          my $MTItems =  $decryptedData[82] + ($decryptedData[83] * 0x100);
          my @MTItems = &showMTItems($MTItems);
          print "MT Items: " . join(',',@MTItems) . "\n";
          #$decryptedData[82-109]; unknown, but in pairs
          # Interestingly, if the player relations have never been set, the
          # player relations length will be 0, with no bytes after it
          # For the player relations values
          # So the result here CAN be 0.
          my $playerRelationsLength = $decryptedData[112];
          if ( $playerRelationsLength ) { 
            for (my $i = 1; $i <= $playerRelationsLength; $i++) {
              my $id = $i-1;
              if ($id == $playerId) { next; } # Skip for self
              print "Player " . $id . ": " . &showPlayerRelations($decryptedData[$i+112]) . "\n";
            } 
          } else { print "Player Relations never set\n"; }
        }
      }
      # END OF MAGIC
    }
    $offset = $offset + (2 + $size); 
  }
  return \@outBytes;
}

