#!/usr/bin/perl
#
########################################################
#
# oracle_dataguard_broker.pl
#
# Checkmk agent plugin for Oracle Data Guard Broker monitoring.
# Self-contained: all functions inlined, no library deps.
#
# Metrics collected:
#   5100 - DG configuration status         (show configuration)
#   5110 - DG database status              (show database 'SID')
#   5120 - Inconsistent properties count   (show database 'SID' 'InconsistentProperties')
#   5130 - Inconsistent log xpt props      (show database 'SID' 'InconsistentLogXptProps')
#
# Output format (sep=124 i.e. pipe):
#   <<<oracle_dataguard_broker:sep(124)>>>
#   SID|METRIC|VALUE|OPTION1|OPTION2|OPTION3|OPTION4|OPTION5
#
########################################################

use strict;
use warnings;

our $PROGRAMNAME = "oracle_dataguard_broker.pl";

##################################################################
# Platform helpers
##################################################################

sub is_windows { return ( $^O eq "MSWin32" ) ? 1 : 0; }
sub is_unix    { return ( $^O =~ /hpux|linux|aix|solaris/ ) ? 1 : 0; }

##################################################################
# Utility functions
##################################################################

sub trim
{
    my @out = @_;
    for (@out)
    {
        if ( defined $_ )
        {
            s/^\s+//;
            s/\s+$//;
        }
    }
    return wantarray ? @out : $out[0];
}

sub make_ospath
{
    my $path = $_[0];
    return "" unless defined $path;
    chomp $path;
    $path =~ s/"//g;
    if ( is_windows() )
    {
        $path =~ s/\//\\/g;
        $path =~ s/\\{2,}/\\/g;
    }
    else
    {
        $path =~ s/\/{2,}/\//g;
    }
    return $path;
}

sub sanitise_option
{
    my $s = defined $_[0] ? $_[0] : "";
    $s =~ s/\|/?/g;
    return $s;
}

sub truncate_str
{
    my ( $s, $max ) = @_;
    $max //= 512;
    if ( length($s) > $max )
    {
        $s = substr( $s, 0, $max - 4 ) . " ...";
    }
    return $s;
}

##################################################################
# Temp directory
##################################################################

sub get_temp_dir
{
    return make_ospath(
        $ENV{MK_TEMPDIR}
        || ( is_windows()
            ? ( $ENV{TEMP} || $ENV{TMP} || 'C:\Windows\Temp' )
            : '/tmp' )
    );
}

##################################################################
# Read non-empty trimmed lines from a file
##################################################################

sub read_file_lines
{
    my ($path) = @_;
    my @lines;
    return @lines unless defined $path && -r $path;
    open( my $fh, "<", $path ) or return @lines;
    while (<$fh>)
    {
        chomp;
        my $line = trim($_);
        push @lines, $line if length $line;
    }
    close($fh);
    return @lines;
}

##################################################################
# Oracle instance discovery
# Returns list of hashrefs { SID => ..., ORAHOME => ... }
# filtered to homes that contain dgmgrl.
##################################################################

sub read_oratab
{
    my $oratab = "";
    for my $candidate ( "/etc/oratab", "/var/opt/oracle/oratab" )
    {
        if ( -r $candidate )
        {
            $oratab = $candidate;
            last;
        }
    }
    my @entries;
    return @entries unless $oratab;

    open( my $fh, "<", $oratab ) or return @entries;
    while (<$fh>)
    {
        chomp;
        s/^\s+//; s/#.*//; s/\s+$//;
        next unless length;
        my ( $sid, $home ) = split( /:/, $_, 3 );
        next unless defined $sid && defined $home;
        $sid  = trim($sid);
        $home = trim($home);
        next if $sid =~ /^\+/;    # skip ASM / Grid entries
        next unless length($home) && $home ne "N";
        push @entries, { SID => $sid, ORAHOME => $home };
    }
    close($fh);
    return @entries;
}

sub has_dgmgrl
{
    my ($orahome) = @_;
    my $dgmgrl = make_ospath( $orahome . "/bin/dgmgrl" . ( is_windows() ? ".exe" : "" ) );
    return -e $dgmgrl ? 1 : 0;
}

sub find_oracle_instances
{
    my @instances;
    my %seen;

    for my $e ( read_oratab() )
    {
        my $key = lc("$e->{SID}:$e->{ORAHOME}");
        next if $seen{$key}++;
        push @instances, $e if has_dgmgrl( $e->{ORAHOME} );
    }

    if ( is_windows() )
    {
        for my $hive (
            'HKEY_LOCAL_MACHINE\\SOFTWARE\\ORACLE',
            'HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\ORACLE'
          )
        {
            my $current_home = "";
            open( my $reg, "reg query \"$hive\" /s 2>nul |" ) or next;
            while (<$reg>)
            {
                chomp;
                if (/ORACLE_HOME\s+REG_SZ\s+(.*)/i)
                {
                    $current_home = trim($1);
                }
                elsif (/ORACLE_SID\s+REG_SZ\s+(.*)/i && $current_home)
                {
                    my $sid = trim($1);
                    my $key = lc("$sid:$current_home");
                    unless ( $seen{$key}++ )
                    {
                        push @instances, { SID => $sid, ORAHOME => $current_home }
                            if has_dgmgrl($current_home);
                    }
                }
            }
            close($reg);
        }
    }

    if ( $ENV{ORACLE_SID} && $ENV{ORACLE_HOME} )
    {
        my $key = lc("$ENV{ORACLE_SID}:$ENV{ORACLE_HOME}");
        unless ( $seen{$key}++ )
        {
            push @instances, { SID => $ENV{ORACLE_SID}, ORAHOME => $ENV{ORACLE_HOME} }
                if has_dgmgrl( $ENV{ORACLE_HOME} );
        }
    }

    return @instances;
}

##################################################################
# Oracle environment setup
##################################################################

my $orig_path = $ENV{PATH} // "";

sub set_oracle_env
{
    my ($inst) = @_;
    my $orahome = $inst->{ORAHOME};

    $ENV{ORACLE_SID}         = $inst->{SID};
    $ENV{ORACLE_HOME}        = $orahome;
    $ENV{LD_LIBRARY_PATH}    = "$orahome/lib";
    $ENV{LIBPATH}            = "$orahome/lib";    # AIX
    $ENV{SRVM_PROPERTY_DEFS} = "-Duser.language=en -Duser.country=US";
    $ENV{NLS_LANG}           = "AMERICAN_AMERICA";

    my $bin = make_ospath("$orahome/bin");
    $ENV{PATH} = is_windows() ? "$bin;$orig_path" : "$bin:$orig_path";
}

##################################################################
# Check whether Data Guard Broker is enabled for this instance.
# Queries dg_broker_start from V$PARAMETER via SQL*Plus.
# Returns 1 if TRUE, 0 otherwise (broker absent, disabled, or
# SQL*Plus unavailable).
##################################################################

sub is_broker_enabled
{
    my ( $orahome, $sid ) = @_;

    my $sqlplus = make_ospath( $orahome . "/bin/sqlplus" . ( is_windows() ? ".exe" : "" ) );
    return 0 unless -e $sqlplus;

    my $tmp      = get_temp_dir();
    my $pid      = $$;
    my $sql_file = make_ospath("$tmp/oracle_dgbroker_chk_${sid}_${pid}.sql");
    my $out_file = make_ospath("$tmp/oracle_dgbroker_chk_${sid}_${pid}.out");

    open( my $fh, ">", $sql_file ) or return 0;
    print $fh "SET PAGESIZE 0 FEEDBACK OFF HEADING OFF VERIFY OFF\n";
    print $fh "SELECT VALUE FROM V\$PARAMETER WHERE NAME = 'dg_broker_start';\n";
    print $fh "EXIT\n";
    close($fh);
    chmod 0600, $sql_file unless is_windows();

    my $null = is_windows() ? "nul" : "/dev/null";
    system("$sqlplus -s / as sysdba \@$sql_file 1>$out_file 2>$null");

    my @output = read_file_lines($out_file);
    unlink $sql_file if -e $sql_file;
    unlink $out_file if -e $out_file;

    return ( grep { /^TRUE$/i } @output ) ? 1 : 0;
}

##################################################################
# Metric implementations
##################################################################

# 5100 - show configuration: Configuration Status
# Value: 0 = SUCCESS, 1 = WARNING, 2 = ERROR
sub metric5100
{
    my ( $sid, $spool ) = @_;

    my @dat    = read_file_lines( $spool->{show_conf} );
    my $status = "";

    for ( my $i = 1; $i < scalar @dat; $i++ )
    {
        if ( $dat[ $i - 1 ] =~ /^\s*Configuration Status:/ )
        {
            $status = trim( $dat[$i] );
        }
    }

    my $value;
    if ($status)
    {
        if    ( $status =~ /^SUCCESS/i ) { $value = 0; }
        elsif ( $status =~ /^WARNING/i ) { $value = 1; }
        elsif ( $status =~ /^ERROR/i )   { $value = 2; }
    }

    return undef unless defined $value;

    return {
        OBJECT  => $sid,
        NUMBER  => 5100,
        VALUE   => $value,
        OPTION1 => "STATUS=" . sanitise_option( truncate_str($status) ),
    };
}

# 5110 - show database 'SID' + 'StatusReport': Database Status
# Value: 0 = SUCCESS, 1 = WARNING, 2 = ERROR
sub metric5110
{
    my ( $sid, $spool ) = @_;

    my @show_db       = read_file_lines( $spool->{show_db} );
    my @status_report = read_file_lines( $spool->{StatusReport} );

    my ( $status, $errorline );

    for ( my $i = 1; $i < scalar @show_db; $i++ )
    {
        if ( $show_db[ $i - 1 ] =~ /^\s*Database Error\(s\):/ )
        {
            $errorline = trim( $show_db[$i] );
        }
        if ( $show_db[ $i - 1 ] =~ /^\s*Database Status:/ )
        {
            $status = trim( $show_db[$i] );
        }
    }

    return undef unless $status;

    my $value;
    if    ( $status =~ /^SUCCESS/i ) { $value = 0; }
    elsif ( $status =~ /^WARNING/i ) { $value = 1; }
    elsif ( $status =~ /^ERROR/i )   { $value = 2; }

    return undef unless defined $value;

    my $report = "";
    if ( $value > 0 )
    {
        for (@status_report)
        {
            next if /^\s*STATUS REPORT/;
            my ( $inst_name, $severity, $error_text ) = split( " ", $_, 3 );
            if ( $error_text && $inst_name eq $sid )
            {
                $report .= "$severity: $error_text; ";
            }
        }
    }

    return {
        OBJECT  => $sid,
        NUMBER  => 5110,
        VALUE   => $value,
        OPTION1 => "STATUS="    . sanitise_option( truncate_str($status) ),
        OPTION2 => "REPORT="    . sanitise_option( truncate_str($report) ),
        OPTION3 => defined $errorline
            ? "ERRORLINE=" . sanitise_option( truncate_str($errorline) )
            : "None",
    };
}

# 5120 - show database 'SID' 'InconsistentProperties'
# Value: count of inconsistent properties (0 = healthy)
sub metric5120
{
    my ( $sid, $spool ) = @_;

    my @dat       = read_file_lines( $spool->{InconsistentProperties} );
    my $value     = 0;
    my $errorline = "";

    for (@dat)
    {
        next if /^\s*INCONSISTENT PROPERTIES/;
        my ( $inst_name, $property ) = split( " ", $_, 3 );
        if ( $property && $inst_name eq $sid )
        {
            $value++;
            $errorline .= "$property ";
        }
    }

    return {
        OBJECT  => $sid,
        NUMBER  => 5120,
        VALUE   => $value,
        OPTION1 => $errorline
            ? "ERRORLINE=InconsistentProperties: " . sanitise_option( truncate_str($errorline) )
            : "None",
    };
}

# 5130 - show database 'SID' 'InconsistentLogXptProps'
# Value: count of inconsistent log transport properties (0 = healthy)
sub metric5130
{
    my ( $sid, $spool ) = @_;

    my @dat       = read_file_lines( $spool->{InconsistentLogXptProps} );
    my $value     = 0;
    my $errorline = "";

    for (@dat)
    {
        next if /^\s*INCONSISTENT LOG TRANSPORT PROPERTIES/;
        my ( $inst_name, $standby, $property ) = split( " ", $_, 4 );
        if ( $property && $inst_name eq $sid )
        {
            $value++;
            $errorline .= "$standby:$property ";
        }
    }

    return {
        OBJECT  => $sid,
        NUMBER  => 5130,
        VALUE   => $value,
        OPTION1 => $errorline
            ? "ERRORLINE=InconsistentLogXptProps (StandbyName:PropertyName): "
              . sanitise_option( truncate_str($errorline) )
            : "None",
    };
}

##################################################################
# Run dgmgrl for one instance and collect all metrics.
# Returns a list of metric hashrefs.
##################################################################

sub collect_data
{
    my ($inst) = @_;
    my $sid     = $inst->{SID};
    my $orahome = $inst->{ORAHOME};

    set_oracle_env($inst);

    return () unless is_broker_enabled( $orahome, $sid );

    my $tmp = get_temp_dir();
    my $pid = $$;

    my $sql_file = make_ospath("$tmp/oracle_dgbroker_${sid}_${pid}.sql");
    my $std_file = make_ospath("$tmp/oracle_dgbroker_${sid}_${pid}.std");
    my $err_file = make_ospath("$tmp/oracle_dgbroker_${sid}_${pid}.err");

    my %spool;
    for my $name (qw(connect show_conf show_db StatusReport InconsistentProperties InconsistentLogXptProps))
    {
        $spool{$name} = make_ospath("$tmp/oracle_dgbroker_${name}_${sid}_${pid}.lst");
    }

    open( my $sql_fh, ">", $sql_file ) or do {
        warn "$PROGRAMNAME: cannot write temp script '$sql_file': $!\n";
        return ();
    };
    print $sql_fh "spool $spool{connect} ;\n";
    print $sql_fh "connect / as sysdg ;\n";
    print $sql_fh "spool $spool{show_conf} ;\n";
    print $sql_fh "show configuration;\n";
    print $sql_fh "spool $spool{show_db} ;\n";
    print $sql_fh "show database '${sid}';\n";
    print $sql_fh "spool $spool{StatusReport} ;\n";
    print $sql_fh "show database '${sid}' 'StatusReport';\n";
    print $sql_fh "spool $spool{InconsistentProperties} ;\n";
    print $sql_fh "show database '${sid}' 'InconsistentProperties';\n";
    print $sql_fh "spool $spool{InconsistentLogXptProps} ;\n";
    print $sql_fh "show database '${sid}' 'InconsistentLogXptProps';\n";
    close($sql_fh);
    chmod 0600, $sql_file unless is_windows();

    my $dgmgrl = make_ospath("$orahome/bin/dgmgrl" . ( is_windows() ? ".exe" : "" ));
    system("$dgmgrl -silent \@$sql_file 1>$std_file 2>$err_file");

    my @connect_lines = read_file_lines( $spool{connect} );
    my $connected     = grep { /^Connected to/i } @connect_lines;

    my @results;

    if ($connected)
    {
        for my $m (
            metric5100( $sid, \%spool ),
            metric5110( $sid, \%spool ),
            metric5120( $sid, \%spool ),
            metric5130( $sid, \%spool ),
          )
        {
            push @results, $m if defined $m;
        }
    }
    else
    {
        my $error = join( " ", @connect_lines );
        warn "$PROGRAMNAME: dgmgrl connect failed for SID '$sid': "
            . substr( $error, 0, 256 ) . "\n";
    }

    for my $f ( $sql_file, $std_file, $err_file, values %spool )
    {
        unlink $f if defined $f && -e $f;
    }

    return @results;
}

##################################################################
# Format one metric result as a pipe-delimited output line.
##################################################################

sub format_output_line
{
    my $r = $_[0];
    return $r->{OBJECT} . "|"
         . $r->{NUMBER}  . "|"
         . $r->{VALUE}   . "|"
         . ( $r->{OPTION1} // "None" ) . "|"
         . ( $r->{OPTION2} // "None" ) . "|"
         . ( $r->{OPTION3} // "None" ) . "|"
         . ( $r->{OPTION4} // "None" ) . "|"
         . ( $r->{OPTION5} // "None" ) . "\n";
}

##################################################################
# MAIN
##################################################################

$ENV{SRVM_PROPERTY_DEFS} = "-Duser.language=en -Duser.country=US";
$ENV{NLS_LANG}           = "AMERICAN_AMERICA";

print "<<<oracle_dataguard_broker:sep(124)>>>\n";

my @instances = find_oracle_instances();
exit 0 unless @instances;

for my $inst (@instances)
{
    for my $r ( collect_data($inst) )
    {
        print format_output_line($r);
    }
}
