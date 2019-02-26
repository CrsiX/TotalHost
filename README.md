# TotalHost
Stars! TotalHost Web-based Turn Management

Stars! (https://en.wikipedia.org/wiki/Stars!) is a classic, turn-based, space-based 4X game, written for Windows, and originally designed to play hostseat or PBEM. 

TotalHost, much like AutoHost, is a web-based interface for game and turn-management. TH builds off the concept of Autohost, 
but adds a nubmer of features such as: 
- Web-based game creation
- More options for host, player and game management
- A Player-pause system, permitting ergulation of player pauses, much like timeouts in sports. 
- The ability to download the game history (to better recreate the .H file, view in retrospect, and/or recover from system failure).

For simplicity, the entire implementation is on a Windows VM running Apache, and ODBC calls to an Access database. 
The entire implementation is in Perl.

I began this project probably 20 years ago as a stop-and-start work, and I'm not a programmer. 
The code therefore has different coding styles and methodologies.  The Stars! community has historically been very 
closed-source,  primarily due to trying to protect the encryption model  and prevent hacking the game. 
This in turn has stifled development of tools and utilities.  Towards that end, I'm open-sourcing TotalHost, warts and all.

TBD:
While the core code already exists as standalone modules, integrating player password resets (for easy player-replacement) 
and movie creation into the web interface.

If I ever get really motivated, I'll separate the code base into the web front end running on a Linux box with MariaDB, 
and a backend running Wnidows (to run the Stars! exe).
