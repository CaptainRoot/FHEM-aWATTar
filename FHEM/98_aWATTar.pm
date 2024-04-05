package main;

use strict;
use warnings;
use Data::Dumper;
use utf8;
use Encode qw( encode_utf8 );
use HttpUtils;
use JSON;
use DateTime;
use DateTime::Format::Strptime;
use List::Util qw(max);
use Date::Parse;

my %Awattar_gets = (
    update         => " "
);

my %Awattar_sets = (
    start        => " ",
    stop         => " ",
    interval     => " "
);

my %url = (
#$ curl "https://api.awattar.de/v1/marketdata"
#Liefert die Strompreisdaten von Jetzt bis zu 24 Stunden in die Zukunft.

#$ curl "https://api.awattar.de/v1/marketdata?start=1636329600000"
#Liefert die Strompreise von 08.11.2021 00:00:00 - 09.11.2021 00:00:00 (24 Stunden).

#$ curl "https://api.awattar.de/v1/marketdata?start=1636329600000&end=1636498800000"
#Liefert die Strompreise von 08.11.2021 00:00:00 bis 10.11.2021 00:00:00 (48 Stunden).
    #getPriceValue => 'https://api.voltego.de/market_data/day_ahead/DE_LU/60?from=#fromDate##TimeZone#&tz=#TimeZone#&unit=EUR-ct_kWh',
    getPriceValue => 'https://api.awattar.de/v1/marketdata?start=#startEpoch#&end=#endEpoch#',
    #getPriceValue => 'https://api.awattar.de/v1/marketdata',
);

sub Awattar_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}     = 'Awattar_Define';
    $hash->{UndefFn}   = 'Awattar_Undef';
    $hash->{SetFn}     = 'Awattar_Set';
    $hash->{GetFn}     = 'Awattar_Get';
    $hash->{AttrFn}    = 'Awattar_Attr';
    $hash->{AttrList}  =
      'showEPEXSpot:yes,no '
	. 'showWithTax:yes,no '
	. 'showWithLeviesTaxes:yes,no '
	. 'showCurrentHour:yes,no '
	. 'showNextHour:yes,no '
	. 'showPreviousHour:yes,no '
    . 'TaxRate '
	. 'LeviesTaxes_ct '
	. 'NetCosts_ct '
	.$readingFnAttributes;

    Log 3, "Awattar module initialized.";
}

sub Awattar_Define($$) {
    my ( $hash, $def ) = @_;
    my @param = split( "[ \t]+", $def );
    my $name  = $hash->{NAME};

    Log3 $name, 3, "Awattar_Define $name: called ";

    my $errmsg = '';

    # Check parameter(s) - Must be min 2 in total (counts strings not purly parameter, interval is optional)
    if ( int(@param) < 2 ) {
        $errmsg = return "syntax error: define <name> Awattar [Interval]";
        Log3 $name, 1, "Awattar $name: " . $errmsg;
        return $errmsg;
    }

    #Check if interval is set and numeric.
    #If not set -> set to 600 seconds
    #If less then 60 seconds set to 6000
    #If not an integer abort with failure.
    my $interval = 600;

    if ( defined $param[2] ) {
        if ( $param[2] =~ /^\d+$/ ) {
            $interval = $param[2];
        }
        else {
            $errmsg = "Specify valid integer value for interval. Whole numbers > 60 only. Format: define <name> Awattar [interval]";
            Log3 $name, 1, "Awattar $name: " . $errmsg;
            return $errmsg;
        }
    }

    if ( $interval < 60 ) { $interval = 600; }
    $hash->{INTERVAL} = $interval;

    readingsSingleUpdate( $hash, 'state', 'Undefined', 0 );

    CommandAttr(undef, $name.' showEPEXSpot yes') if ( AttrVal($name,'showEPEXSpot','none') eq 'none' );
    CommandAttr(undef, $name.' showWithTax no') if ( AttrVal($name,'showWithTax','none') eq 'none' );
    CommandAttr(undef, $name.' showWithLeviesTaxes yes') if ( AttrVal($name,'showWithLeviesTaxes','none') eq 'none' );

    CommandAttr(undef, $name.' showCurrentHour yes') if ( AttrVal($name,'v','none') eq 'none' );
    CommandAttr(undef, $name.' showNextHour yes') if ( AttrVal($name,'showNextHour','none') eq 'none' );
    CommandAttr(undef, $name.' showPreviousHour yes') if ( AttrVal($name,'showPreviousHour','none') eq 'none' );

    CommandAttr(undef, $name.' TaxRate 19') if ( AttrVal($name,'TaxRate','none') eq 'none' );
    CommandAttr(undef, $name.' LeviesTaxes_ct 0.00') if ( AttrVal($name,'LeviesTaxes_ct','none') eq 'none' );
    CommandAttr(undef, $name.' NetCosts_ct 0.00') if ( AttrVal($name,'NetCosts_ct','none') eq 'none' );

    RemoveInternalTimer($hash);

    Log3 $name, 1,
      sprintf( "Awattar_Define %s: Starting timer with interval %s",
      $name, InternalVal( $name, 'INTERVAL', undef ) );

    InternalTimer( gettimeofday() + 15, "Awattar_UpdateDueToTimer", $hash ) if ( defined $hash );

    InternalTimer( gettimeofday() + 45, "Awattar_HourTaskTimer", $hash ) if ( defined $hash );

    return undef;
}

sub Awattar_Undef($$) {
    my ( $hash, $arg ) = @_;

    RemoveInternalTimer($hash);
    return undef;
}


sub Awattar_Get($@) {
    my ( $hash, $name, @args ) = @_;

    return '"get Awattar" needs at least one argument' if ( int(@args) < 1 );

    my $opt = shift @args;
    if ( !$Awattar_gets{$opt} ) {
        my @cList = keys %Awattar_gets;
        return "Unknown! argument $opt, choose one of " . join( " ", @cList );
    }

    my $cmd = $args[0];
    my $arg = $args[1];

    if ( $opt eq "update" ) {

        Log3 $name, 3, "Awattar_Get Awattar_RequestUpdate $name: Updating ....s";
        $hash->{LOCAL} = 1;
        #($hash);

        Awattar_RequestUpdate($hash);

        delete $hash->{LOCAL};
        return undef;

    }
    else {

        my @cList = keys %Awattar_gets;
        return "Unknown v2 argument $opt, choose one of " . join( " ", @cList );
    }
}

sub Awattar_Set($@) {
    my ( $hash, $name, @param ) = @_;

    return '"set $name" needs at least one argument' if ( int(@param) < 1 );

    my $opt   = shift @param;
    my $value = join( "", @param );

    if ( !defined( $Awattar_sets{$opt} ) ) {
        my @cList = keys %Awattar_sets;
        return "Unknown argument $opt, choose one of start stop interval";
    }

    if ( $opt eq "start" ) {

        readingsSingleUpdate( $hash, 'state', 'Started', 0 );

        RemoveInternalTimer($hash);

        $hash->{LOCAL} = 1;
        Awattar_RequestUpdate($hash);
        delete $hash->{LOCAL};

        Awattar_HourTaskTimer($hash);

        InternalTimer( gettimeofday() + InternalVal( $name, 'INTERVAL', undef ), "Awattar_UpdateDueToTimer", $hash );

        Log3 $name, 1,
          sprintf( "Awattar_Set %s: Updated readings and started timer to automatically update readings with interval %s",
            $name, InternalVal( $name, 'INTERVAL', undef ) );

    }
    elsif ( $opt eq "stop" ) {

        RemoveInternalTimer($hash);

        Log3 $name, 1,"Awattar_Set $name: Stopped the timer to automatically update readings";

        readingsSingleUpdate( $hash, 'state', 'Initialized', 0 );

        return undef;

    }
    elsif ( $opt eq "interval" ) {

        my $interval = shift @param;

        $interval = 60 unless defined($interval);
        if ( $interval < 5 ) { $interval = 5; }

        Log3 $name, 1, "Awattar_Set $name: Set interval to" . $interval;

        $hash->{INTERVAL} = $interval;
    }

    readingsSingleUpdate( $hash, 'state', 'Initialized', 0 );
    return undef;

}

sub Awattar_Attr(@) {
    return undef;
}

sub Awattar_UpdatePricesCallback($) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err ne "" )    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        Log3 $name, 1,
            "error while requesting "
          . $param->{url}
          . " - $err";    # Eintrag fürs Log
        readingsSingleUpdate( $hash, "state", "ERROR", 1 );
        return undef;
    }

    Log3 $name, 3, "Received non-blocking data from Awattar for prices ";

    Log3 $name, 4, "FHEM -> Awattar: " . $param->{url};
    Log3 $name, 4, "FHEM -> Awattar: " . $param->{message} if ( defined $param->{message} );
    Log3 $name, 4, "Awattar -> FHEM: " . $data;
    Log3 $name, 5, '$err: ' . $err;
    Log3 $name, 5, "method: " . $param->{method};

    if ( !defined($data) or $param->{method} eq 'DELETE' ) {
        return undef;
    }

    eval {
        my $d = decode_json($data) if ( !$err );

        Log3 $name, 5, 'Decoded: ' . Dumper($d);

        if ( defined $d && ref($d) eq "HASH" && defined $d->{errors} )
        {
            log 1, Dumper $d;

            readingsSingleUpdate( $hash, 'state', "Error: $d->{errors}[0]->{code} / $d->{errors}[0]->{title}",1 );

            return undef;
        }

        my $local_time_zone = DateTime::TimeZone->new( name => 'local' );
        Log3 $name, 5, 'TimeZoneInfo 1: ' . $local_time_zone;
        Log3 $name, 5, 'TimeZoneInfo 2: ' . $local_time_zone->name;

        # Aktuelles Datum und Uhrzeit erhalten
        my $dt  = DateTime->today;
        my $dtt = DateTime->today->add(days => 1);

        # Formatierter Datums- und Uhrzeitstring
        my $today_Day = $dt->strftime('%d'); #01-31
        my $today_Tomorrow = $dtt->strftime('%d'); #01-31

        my %prices;
        $prices{0}{'Min'}  = undef;
        $prices{0}{'Max'}  = undef;
        $prices{0}{'Date'} = undef;

        $prices{1}{'Min'}  = undef;
        $prices{1}{'Max'}  = undef;
        $prices{1}{'Date'} = undef;

        my %times;
        my %dates;
        
        $dates{0} = undef;
        $dates{1} = undef;

        # Auf die Liste der Elemente zugreifen
        my $data = $d->{'data'};

        # Iteriere durch die Elemente und gib den Begin-Zeitpunkt und den Preis aus
        foreach my $element (@$data) {

            my $begin = $element->{'start_timestamp'};
            my $price = $element->{'marketprice'};
            
            # Convert Mwh to kwh
            $price = $price / 1000;

            Log3 $name, 5, "Begin: $begin, Price: $price\n";

            # DateTime-Objekte erstellen
            my $begin_Dt  = DateTime->from_epoch(epoch => ($begin / 1000), time_zone => $local_time_zone);
            my $begin_Hour = $begin_Dt->strftime('%H'); #00-23
            my $begin_Time = $begin_Dt->strftime('%H:%M'); #00-23:00-59
            my $begin_Day  = $begin_Dt->strftime('%d'); #01-31
            my $fc_Date    = $begin_Dt->ymd; # Retrieves date as a string in 'yyyy-mm-dd' format

            if($today_Day == $begin_Day || $today_Tomorrow == $begin_Day){

                my $index;

                if($today_Day == $begin_Day){
                    $index = 0;
                }
                else {
                    $index = 1;
                }
                
                Log3 $name, 5, 'Begin_Hour : ' . $begin_Hour;
                Log3 $name, 5, 'Begin_Time : ' . $begin_Time;
                Log3 $name, 5, 'Begin_Day  : ' . $begin_Day;
                Log3 $name, 5, 'fc_Date    : ' . $fc_Date;

                $prices{$index}{$begin_Hour} = $price;
                $times{$index}{$begin_Hour} = $begin_Time;
                $dates{$index} = $fc_Date if ( !defined $dates{$index} );

                if(!defined($prices{$index}{'Min'}) || $price < $prices{$index}{'Min'}){
                    $prices{$index}{'Min'} = $price;
                }

                if(!defined($prices{$index}{'Max'}) || $price > $prices{$index}{'Max'}){
                    $prices{$index}{'Max'} = $price;
                }
            }
        }

        readingsBeginUpdate($hash);

        for my $day (keys(%prices)) {

            my $hours = $prices{$day};

            for my $hour (keys(%$hours)) {

                my $price = $prices{$day}{$hour};
                #my $beginTime = $times{$day}{$hour};
                my $date = $dates{$day};

                my $showEPEXSpot = AttrVal($name, 'showEPEXSpot', 'no');

                if ($showEPEXSpot eq 'yes') {

                    my $reading = 'EPEXSpot_ct_'. $day. '_'. $hour;

                    Log3 $name, 5, 'Generate Reading; '.$reading.' with price: '.$price;

                    readingsBulkUpdate( $hash, $reading, $price );
                    #readingsBulkUpdate( $hash, $reading.'_Time', $beginTime ) if ( defined $beginTime );
                    readingsBulkUpdate( $hash, 'EPEXSpot_ct_'. $day.'_Date', $date ) if ( defined $date );
                }
                else{
                    #delete redings when show is set to no
                    deleteReadingspec ($hash, "EPEXSpot_ct_.*"    ) if ( $showEPEXSpot eq 'no' );
                }

                my $showWithTax = AttrVal($name, 'showWithTax', 'no');
                my $taxRate     = AttrVal($name, 'TaxRate', undef);

                if ($showWithTax eq 'yes' && defined($taxRate)){

                    my $reading = 'EPEXSpotTax_ct_'. $day. '_'. $hour;
                    my $priceWithTax = $price * (1 + ($taxRate / 100));

                    Log3 $name, 5, 'Generate Reading; '.$reading.' with price: '.$priceWithTax;

                    readingsBulkUpdate( $hash, $reading, $priceWithTax );
                    #readingsBulkUpdate( $hash, $reading.'_Time', $beginTime ) if ( defined $beginTime );
                    readingsBulkUpdate( $hash, 'EPEXSpotTax_ct_'. $day.'_Date', $date ) if ( defined $date );
                }
                else{
                    #delete redings when show is set to no
                    deleteReadingspec ($hash, "EPEXSpotTax_ct_.*" ) if ( $showWithTax eq 'no' );
                }

                my $showWithLeviesTaxes = AttrVal($name, 'showWithLeviesTaxes', 'no');
                my $leviesTaxes_ct      = AttrVal($name, 'LeviesTaxes_ct', 0.0);
                my $netCosts_ct         = AttrVal($name, 'NetCosts_ct', 0.0);

                if ($showWithLeviesTaxes eq 'yes' && defined($taxRate)){

                    my $reading = 'TotalPrice_ct_'. $day. '_'. $hour;
                    my $priceTotal = ($price + $leviesTaxes_ct + $netCosts_ct)  * (1 + ($taxRate / 100));

                    Log3 $name, 5, 'Generate Reading; '.$reading.' with price: '.$priceTotal;

                    readingsBulkUpdate( $hash, $reading, $priceTotal );
                    #readingsBulkUpdate( $hash, $reading.'_Time', $beginTime ) if ( defined $beginTime );
                    readingsBulkUpdate( $hash, 'TotalPrice_ct_'. $day.'_Date', $date ) if ( defined $date );
                }
                else{
                    #delete redings when show is set to no
                    deleteReadingspec ($hash, "TotalPrice_ct_.*"  ) if ( $showWithLeviesTaxes eq 'no' );
                }
            }
        }

        readingsBulkUpdate( $hash, "TimeZone",     $local_time_zone->name );
        readingsBulkUpdate( $hash, "LastUpdate",   DateTime->now(time_zone => $local_time_zone)->strftime('%Y-%m-%d %H:%M:%S %z'));
        readingsBulkUpdate( $hash, "NextUpdate",   DateTime->now(time_zone => $local_time_zone)->add(seconds => InternalVal( $name, 'INTERVAL', 0 ))->strftime('%Y-%m-%d %H:%M:%S %z') );

        #delete old readings when values are not available
        deleteReadingspec ($hash, "EPEXSpot_ct_0.*") if ( !defined $prices{0}{'Min'} );
        deleteReadingspec ($hash, "EPEXSpot_ct_1.*") if ( !defined $prices{1}{'Min'} );

        deleteReadingspec ($hash, "EPEXSpotTax_ct_0.*") if ( !defined $prices{0}{'Min'} );
        deleteReadingspec ($hash, "EPEXSpotTax_ct_1.*") if ( !defined $prices{1}{'Min'} );

        deleteReadingspec ($hash, "TotalPrice_ct_0.*") if ( !defined $prices{0}{'Min'} );
        deleteReadingspec ($hash, "TotalPrice_ct_1.*") if ( !defined $prices{1}{'Min'} );

        readingsEndUpdate( $hash, 1 );
    };

    if ($@) {
        Log3 $name, 1, 'Failure decoding: ' . $@;
    }

    return undef;
}

sub Awattar_UpdateDueToTimer($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};

    #local allows call of function without adding new timer.
    #must be set before call ($hash->{LOCAL} = 1) and removed after (delete $hash->{LOCAL};)
    if ( !$hash->{LOCAL} ) {
        RemoveInternalTimer($hash, "Awattar_UpdateDueToTimer");

        InternalTimer( gettimeofday() + InternalVal( $name, 'INTERVAL', undef ),"Awattar_UpdateDueToTimer", $hash );

        readingsSingleUpdate( $hash, 'state', 'Polling', 0 );
    }

    Awattar_RequestUpdate($hash);
}

sub Awattar_HourTaskTimer($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};

    my @readings = ( 'EPEXSpot_', 'EPEXSpotTax_', 'TotalPrice_' );

    my $timeZone = DateTime::TimeZone->new(name => 'local');

    # currentTime
    my $currentTime = DateTime->now(time_zone => $timeZone);

    $currentTime = $currentTime->set(minute => 0, second => 0);

    my $currentHour = $currentTime->strftime('%H');

    Log3 $name, 5, 'currentHour; '.$currentHour;

    # nextHourTime
    my $nextHourTime = DateTime->now(time_zone => $timeZone);

    $nextHourTime = $nextHourTime->set(minute => 0, second => 0);

    $nextHourTime = $nextHourTime->add(hours => 1, minutes => 1);

    my $nextHour = $nextHourTime->strftime('%H');

    my $hourTaskTimestamp = $nextHourTime->epoch;

    Log3 $name, 5, 'nextHour; '.$nextHour;
    Log3 $name, 5, 'hourTaskTimestamp; '.$hourTaskTimestamp;

    # previousHourTime
    my $previousHourTime = DateTime->now(time_zone => $timeZone);

    $previousHourTime = $previousHourTime->set(minute => 0, second => 0);

    $previousHourTime = $previousHourTime->subtract(hours => 1);

    my $previousHour = $previousHourTime->strftime('%H');

    Log3 $name, 5, 'previousHour; '.$previousHour;

    for my $reading (@readings){

        Log3 $name, 5, 'Reading; '.$reading;

        my $currentPrice  = ReadingsVal($name, $reading.'ct_0_'.$currentHour, undef);
        my $previousPrice = ReadingsVal($name, $reading.'ct_0_'.$previousHour, undef);
        my $nextPrice     = ReadingsVal($name, $reading.'ct_0_'.$nextHour, undef);

        my $showCurrentHour  = AttrVal($name, 'showCurrentHour', 'no');
        my $showPreviousHour = AttrVal($name, 'showPreviousHour', 'no');
        my $showNextHour     = AttrVal($name, 'showNextHour', 'no');

        if ($showCurrentHour eq 'yes' && defined $currentPrice){

            Log3 $name, 5, 'currentPrice; '.$currentPrice;

            Log3 $name, 5, 'Generate Reading; '.$reading."Current_ct";
            Log3 $name, 5, 'Generate Reading; '.$reading."Current_h";

            readingsBeginUpdate($hash);

            readingsBulkUpdate( $hash, $reading."Current_ct", $currentPrice);
            readingsBulkUpdate( $hash, $reading."Current_h",  $currentHour);

            readingsEndUpdate($hash, 1 );
        }

        if ($showPreviousHour eq 'yes' && defined $previousPrice){

            Log3 $name, 5, 'previousPrice; '.$previousPrice;

            Log3 $name, 5, 'Generate Reading; '.$reading."Previous_ct";
            Log3 $name, 5, 'Generate Reading; '.$reading."Previous_h";

            readingsBeginUpdate($hash);

            readingsBulkUpdate( $hash, $reading."Previous_ct", $previousPrice);
            readingsBulkUpdate( $hash, $reading."Previous_h",  $previousHour);

            readingsEndUpdate($hash, 1 );
        }

        if ($showNextHour eq 'yes' && defined $nextPrice){

            Log3 $name, 5, 'nextPrice; '.$nextPrice;

            Log3 $name, 5, 'Generate Reading; '.$reading."Next_ct";
            Log3 $name, 5, 'Generate Reading; '.$reading."Next_h";

            readingsBeginUpdate($hash);

            readingsBulkUpdate( $hash, $reading."Next_ct", $nextPrice);
            readingsBulkUpdate( $hash, $reading."Next_h",  $nextHour);

            readingsEndUpdate($hash, 1 );
        }
    }

    #local allows call of function without adding new timer.
    #must be set before call ($hash->{LOCAL} = 1) and removed after (delete $hash->{LOCAL};)
    if ( !$hash->{LOCAL} ) {

        RemoveInternalTimer($hash, "Awattar_HourTaskTimer");

        InternalTimer( $hourTaskTimestamp, "Awattar_HourTaskTimer", $hash );
    }
}

sub Awattar_RequestUpdate($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( not defined $hash ) {
        Log3 'Awattar', 1,
          "Error on Awattar_RequestUpdate. Missing hash variable";
        return undef;
    }

    Log3 $name, 4, "Awattar_RequestUpdate Called for non-blocking value update. Name: $name";

    # Aktuelles Datum und Uhrzeit erhalten
    my $dt = DateTime->now;

    my $local_time_zone = DateTime::TimeZone->new( name => 'local' );
    my $time_zone = $local_time_zone->name;

    Log3 $name, 5, 'TimeZoneInfo 1: ' . $local_time_zone;
    Log3 $name, 5, 'TimeZoneInfo 2: ' . $time_zone;

    # Beispiel für ein benutzerdefiniertes Format
    my $format = '%Y-%m-%dT00:00:00'; #2023-11-24T00:00:00

    # Set time to midnight (00:00:00)
    $dt->set_hour(0);
    $dt->set_minute(0);
    $dt->set_second(0);

    #subtract 1 hour from dt
    $dt->subtract(hours => 1);

    # Convert DateTime object to epoch
    my $startEpoch = $dt->epoch;
    # convert to ms
    $startEpoch = $startEpoch * 1000;

    Log3 $name, 5, 'Start Epoch Datetime: '.$dt->strftime($format);

    $dt->add(days => 2);
    # Convert DateTime object to epoch
    my $endEpoch = $dt->epoch;
    # convert to ms
    $endEpoch = $endEpoch * 1000;
    
    Log3 $name, 5, 'End Epoch Datetime: '.$dt->strftime($format);

    my $getPriceValueUrl = $url{"getPriceValue"};

	$getPriceValueUrl =~ s/#startEpoch#/$startEpoch/g;
    $getPriceValueUrl =~ s/#endEpoch#/$endEpoch/g;

    my $request = {
        url    => $getPriceValueUrl,
        header => {
            "Content-Type"  => "application/json",
        },
        method   => 'GET',
        timeout  => 2,
        hideurl  => 1,
        callback => \&Awattar_UpdatePricesCallback,
        hash     => $hash
    };

    Log3 $name, 5, 'NonBlocking Request: ' . Dumper($request);

    HttpUtils_NonblockingGet($request);
}


################################################################
#    alle Readings eines Devices oder nur Reading-Regex
#    löschen
################################################################
sub deleteReadingspec {
    my $hash = shift;
    my $spec = shift // ".*";

    my $readingspec = '^'.$spec.'$';

    for my $reading ( grep { /$readingspec/x } keys %{$hash->{READINGS}} ) {
        readingsDelete($hash, $reading);
    }

    return;
}

1;

=pod
=begin html

<a name="Awattar"></a>
<h3>Awattar</h3>
<ul>
    <i>Awattar</i> implements an interface to the Awattar energy price api.
    <br>The plugin can be used to read the hourly energy proces from the Awattar website.
    <br>The following features / functionalities are defined by now when using Awattar:
    <br>
    <a name="Awattardefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Awattar  &lt;interval&gt;</code>
        <br>
        <br> Example: <code>define Awattar Awattar  6000</code>
        <br>
    </ul>
    <br>
    <b>Set</b>
    <br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt;</code>
        <br>
        <br> The <i>set</i> command just offers very limited options. If can be used to control the refresh mechanism. The plugin only evaluates the command. Any additional information is ignored.
        <br>
        <br> Options:
        <ul>
            <li><i>interval</i>
                <br> Sets how often the values shall be refreshed. This setting overwrites the value set during define.</li>
            <li><i>start</i>
                <br> (Re)starts the automatic refresh. Refresh is autostarted on define but can be stopped using stop command. Using the start command FHEM will start polling again.</li>
            <li><i>stop</i>
                <br> Stops the automatic polling used to refresh all values.</li>
        </ul>
    </ul>
    <br>
    <a name="Awattarget"></a>
    <b>Get</b>
    <br>
    <ul>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br>
        <br> You can <i>get</i> the major information from the Awattar cloud.
        <br>
        <br> Options:
        <ul>
           <li><i>update</i>
                <br> This command triggers a single update of the hourly energy prices.
            </li>
            <li><i>newToken</i>
                <br> This command forces to get a new oauth token.</li>
        </ul>
    </ul>
    <br>
        <a name="Awattarattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br>
        <br> You can change the behaviour of the Awattar Device.
        <br>
        <br> Attributes:
        <ul>
            <li><i>showEPEXSpot</i>
                <br> When set to <i>yes</i>, reading <i>EPEXSpot_ct_?_??</i> are generated
                <br/><b>If this attribute is set to <i>no</i> or if the attribute is not existing no readings for <i>EPEXSpot_ct_?_??</i> will be generated..</b>
            </li>
            <li><i>showWithTax</i>
                <br> When set to <i>yes</i>, reading <i>EPEXSpotTax_ct_?_??</i> are generated
                <br/><b>If this attribute is set to <i>no</i> or if the attribute is not existing no readings for <i>EPEXSpotTax_ct_?_??</i> will be generated..</b>
            </li>
            <li><i>showWithLeviesTaxes</i>
                <br> When set to <i>yes</i>, reading <i>TotalPrice_ct_?_??</i> are generated
                <br/><b>If this attribute is set to <i>no</i> or if the attribute is not existing no readings for <i>TotalPrice_ct_?_??</i> will be generated..</b>
            </li>

            <li><i>TaxRate</i>
                <br> Tex rate in precentage, used fpr calculating prices with tax <i>EPEXSpotTax_ct_?_??</i> or <i>TotalPrice_ct_?_??</i>.
                <br/>
            </li>
            <li><i>LeviesTaxes_ct</i>
                <br> Levies and taxes in cents, used fpr calculating <i>TotalPrice_ct_?_??</i>.
            </li>
            <li><i>NetCosts_ct</i>
                <br>Netcosts in cents (without tax), used fpr calculating <i>TotalPrice_ct_?_??</i>.
            </li>
        </ul>
 	</ul>
    <br>
    <a name="Awattarreadings"></a>
    <b>Generated Readings:</b>
		<br>
    <ul>
        <ul>
            <li><b>LastModified</b>
                <br> Time when the energy prices were last updated by Awattar
            </li>
            <li><b>LastUpdate</b>
                <br> Indicates when the last successful request to update the energy prices was made</i>.
            </li>
            <li><b>NextUpdate</b>
                <br>Time when the energy prices will next be queried from Awattar
            </li>
            <li><b>EPEXSpot_ct_0_00 .. EPEXSpot_ct_0_23</b>
                <br> Energy price in cents for today per hour EPEXSpot_ct_0_&lt;hour&gt;
            </li>
            <li><b>EPEXSpot_ct_1_00 .. EPEXSpot_ct_1_23</b>
                <br>Energy price in cents for tommorow per hour EPEXSpot_ct_1_&lt;hour&gt; when available
            </li>
            <li><b>EPEXSpotTax_ct_0_00 .. EPEXSpotTax_ct_0_23</b>
                <br> Energy price including tax in cents for today per hour EPEXSpotTax_ct_0_&lt;hour&gt;
            </li>
            <li><b>EPEXSpotTax_ct_1_00 .. EPEXSpotTax_ct_1_23</b>
                <br>Energy price including taxin cents for tommorow per hour EPEXSpotTax_ct_1_&lt;hour&gt; when available
            </li>
             <li><b>TotalPrice_ct_0_00 .. TotalPrice_ct_0_23</b>
                <br> Energy price including tax, net costs and levies in cents for today per hour TotalPrice_ct_0_&lt;hour&gt;
            </li>
            <li><b>TotalPrice_ct_1_00 .. TotalPrice_ct_1_23</b>
                <br>Energy price including tax, net costs and levies in cents for tommorow per hour TotalPrice_ct_1_&lt;hour&gt; when available
            </li>
            <li><b>TimeZone</b>
                <br> Time zone used for display and evaluation
            </li>
        </ul>
    </ul>
</ul>

=end html

=cut
