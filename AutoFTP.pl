# ----------------------------------------------------------------
# AutoFTP
# Shahryar Rashid
#
# Connects to a Remote Server via FTP and Pulls New Files
# ----------------------------------------------------------------

# Import Modules
use strict;
use warnings;
use Cwd; # Current Working Directory
use Net::FTP; # FTP Connection
use Net::FTP::File; # Provides "isdir" and "isfile" Functions
use Term::ReadKey; # Hides Password Input
use Term::ANSIColor; # Colored Text

# Capture Warnings (Datastream Warnings are Suppressed for Timeout Errors)
my $datastream = 0;
local $SIG{__WARN__} = sub { # Local to Prevent Affecting Other Modules
	my $message = shift;
	print "$message\n" if ($message !~ m/Datastream/i)
};

# Globals
my $server = "SERVER";
my $source = "/DOWNLOADS"; # Remote Folder
my $destination = "C:\\DOWNLOADS"; # Local Folder

my $script = cwd(); # Location of Script
my $limit = 300; # Time in Seconds Until a New Download is Valid
my @queue; # Stores New Detected Files

# Username
# my $user = "USER";
print "\nUsername: ";
chomp(my $user = <STDIN>);

# Password
# my $password = "PASSWORD";
print "Password: ";
ReadMode('noecho');
chomp(my $password = <STDIN>);
ReadMode('restore');

# Connect to Server
print "\nAttempting to Login...\n";
my $ftp = connectFTP($user, $password);
print "Successful!\n\n";

createLog() if (not -e "Log.txt" or -s "Log.txt" == 0);
downloadContent();
updateLog();
	
$ftp->quit;

# Connect to Server
sub connectFTP {
	my ($user, $password) = @_;
	
	my $ftp = Net::FTP->new($server, Debug => 0)
		or die "Cannot Connect to Server: $@";
		  
	$ftp->login($user,$password)
		or die "Cannot Login: ", $ftp->message;
	
	$ftp->cwd($source)
		or die "Cannot Change Working Directory: ", $ftp->message;
	
	$ftp->binary; # Default is ASCII
	
	return $ftp;
}

# Initialize Log With Previously Downloaded Files
sub createLog {
	$ftp->cwd($source)
		or die "Cannot Change Working Directory: ", $ftp->message;
	
	open(my $log, ">", "Log.txt")
		or die "Could Not Create Text File: $!", "\n";
	
	print "Initial Calibration...\n";
	foreach my $file ($ftp->ls()) {		
		while(1) {
			print "Has $file Been Transferred? ";
			chomp(my $response = <STDIN>);
			if ($response =~ m/^Y$/i) {
				$file =~ s/\W//g;  # Removes All Non-Alphanumeric Characters
				print $log "$file\n";
				last;
			}
			elsif ($response =~ m/^N$/i) {
				last;
			}
			else {
				print "Invalid Command\n";
			}
		}
	}
	
	print "\n";	
	close $log;
}

# Update Log With New Downloads
sub updateLog {
	$ftp->cwd($source)
		or die "Cannot Change Working Directory: ", $ftp->message;
	
	chdir $script; # Move to Script Folder
	
	open(my $log, ">", "Log.txt")
		or die "Could Not Open Text File: $!", "\n";
	
	my $failed = join("",@queue);
	foreach my $file ($ftp->ls()) {
		$file =~ s/\W//g;
		print $log "$file\n" if ($failed !~ m/$file/);
	}
	
	close $log;
}

# Download New Content
sub downloadContent {			
	my $downloaded;
	{ # Slurp Log File
		open(my $log, "<", "Log.txt")
			or die "Could Not Open Text File: $!", "\n";
		
		local $/ = undef;
		$downloaded = <$log>;
		close $log;
	}
	
	print "Downloading New Items...\n";
	foreach my $file ($ftp->ls()) {
		my $filtered = $file;
		$filtered =~ s/\W//g; # Used for Log Comparisons
		if ($downloaded !~ m/$filtered/) { # Check for New Content
			print "\nNew File Detected: $file\n";
			push @queue, $filtered;	
			
			print "Checking If File Currently Downloading...\n";		
			if ($ftp->isdir("$source/$file")) { # Download Directory
				if (!directoryActivity($file)) {
					my $size = directorySize($file, 0);
					print "Copying ", sprintf("%.0f", $size/ (10**6)), " MBs\n";
					getDirectory($file, $size);
					print "Download Successful!\n";
					pop @queue;
				}
				else {
					print color("red"), "Cannot Download File at this Time\n", color("reset");
				}
			}
			else { # Download File
				$ftp->cwd($source)
					or die "Cannot Change Working Directory: ", $ftp->message;				
				my $time = $ftp->mdtm($file);
				if (time - $time > $limit) {
					my $size = $ftp->size($file);
					print "Copying ", sprintf("%.0f", $size/ (10**6)), " MBs\n";
					print "Downloading $file\n";
					chdir $destination;					
					getFile($file, $size);
					print "Download Successful!\n";
					pop @queue;
				}
				else {
					print color("red"), "Cannot Download File at this Time\n", color("reset");
				}
			}
		}
	}
	
	print "\nDone!\n";
}

# Recursively Determine Size of a Directory
sub directorySize {
	my ($directory, $size) = @_;

	return if not $ftp->isdir("$source/$directory");
	
	$ftp->cwd("$source/$directory/")
		or die "Cannot Change Working Directory: ", $ftp->message;
		
	foreach my $file ($ftp->ls()) {
		if ($ftp->isfile("$source/$directory/$file")) {
			$size += ($ftp->size($file));
		}
		else {
			$size += directorySize("$directory/$file", $size);
		}
	}
	
	return $size;
}

# Recursively Check Modification Time in a Directory
sub directoryActivity {
	my $directory = shift;
	
	return if not $ftp->isdir("$source/$directory");
	
	$ftp->cwd("$source/$directory/")
		or die "Cannot Change Working Directory: ", $ftp->message;
		
	foreach my $file ($ftp->ls()) {
		if ($ftp->isfile("$source/$directory/$file")) {
			my $time = ($ftp->mdtm($file));
			return 1 if (time - $time < $limit);
		}
		else {
			return 1 if (directoryActivity("$directory/$file"));
		}
	}
	
	return 0; # Safe to Download	
}

# Recursively Download Contents in a Directory
sub getDirectory {
	my $directory = shift;

	return if not $ftp->isdir("$source/$directory");
	
	$ftp->cwd("$source/$directory/")
		or die "Cannot Change Working Directory: ", $ftp->message;
	
	my $folder = $directory;
	$folder =~ s/\//\\/; # Replace Forward Slashes With Back Slashes (For Windows)
	mkdir "$destination\\$folder\\"; # Create Folder on Local System
	chdir "$destination\\$folder\\";
	
	foreach my $file ($ftp->ls()) {
		if ($ftp->isfile("$source/$directory/$file")) {
			my $size = $ftp->size($file);
			print "Downloading $file\n";
			getFile($file, $size);
		}
		else {
			getDirectory("$directory/$file");
		}
	}
}

# Download a File
sub getFile {
	my ($file, $size) = @_; 
	
	my $rwd = $ftp->pwd(); # Remote Working Directory
	
	unless ($ftp->get($file)) {
		if ($ftp->message =~ m/Timeout/i) { # Handle Timeout Errors
			timeoutError($file, $size, $rwd);
		}
		else {
			print "Download Failed: ", $ftp->message;
			updateLog();
			exit;
		}
	}
}

# Handle Timeout Errors
sub timeoutError {
	my ($file, $remoteSize, $rwd) = @_;
	my $localSize = -s $file;
	
	if ($localSize != $remoteSize) { # Download Failed
		$file =~ s/\W//g;
		print "Download Failed Due to Timeout Error\n";
		updateLog();
		exit;
	}
	else { # Reconnect
		print color("yellow"), "Correcting Timeout Error...", color("reset");
		$ftp->quit;
		$ftp = connectFTP($user, $password);
		$ftp->cwd($rwd);
		print color("yellow"), "Successful!\n", color("reset");
	}
}