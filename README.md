# AutoFTP

AutoFTP is a simple Perl script used to pull files periodically from a remote location. In the absence of a log file, the script will
prompt the user for what items have already been transferred. Any file or folder that is not found in the log file will be scanned for
activity and transferred accordingly.

# Configuration

Specify the name of the server, the source, and the destination in the script. By default the script will prompt the user for a username
and password each time. Simply comment out these lines if you wish to manually define these parameters. If needed, you can also adjust
the time limit for when a newly downloaded file is considered valid.
