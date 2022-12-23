#!/usr/bin/perl
use strict;
use Web::Scraper;
use WWW::Mechanize;
use Number::Format qw(:subs);
use DateTime;
use List::MoreUtils qw(uniq);
use utf8;
binmode STDOUT, ':utf8';

my $userid = 'UserID for mypage.bmobile.ne.jp';
my $passwd = 'Password for mypage.bmobile.ne.jp';
my $event = 'IFTTT event name';
my $secret_key = 'IFTTT secret key';

my $dt = DateTime->now(time_zone => 'local');

my $mech = WWW::Mechanize->new();
$mech->get('https://mypage.bmobile.ne.jp/') or die;
$mech->submit_form(
    fields => {
        'josso_username' => $userid,
        'josso_password' => $passwd,
    }
);

my $scraper_phones = scraper {
     process '//optgroup/option', 'options[]' => {
           'i' => '@value',
           'number' => 'TEXT'
     };
};
my $scraper_usage = scraper {
    process '//span/div[1]/div/div[1]/dl[3]/dd/span[1]/span', 'text' => 'TEXT';
};
my $scraper_limit = scraper {
    process '//span/div[1]/div/div[1]/dl[3]/dd/span[2]/span', 'text' => 'TEXT';
};
my $scraper_period = scraper {
    process '//span/div[1]/div/div[1]/dl[3]/dd/span[3]', 'text' => 'TEXT';
};
my $scraper_charge = scraper {
    process '//table/tr[5]/td/span', 'text' => 'TEXT';
};

$mech->get('https://mypage.bmobile.ne.jp/checkout/status') or die;
my $result_phones = $scraper_phones->scrape($mech->content);
my $phone_numbers = {map {$_->{'i'} => $_->{'number'}} @{$result_phones->{'options'}}};
my @keys;
if ($#ARGV == -1) {
    @keys = keys %$phone_numbers;
} else {
    foreach my $key (keys %$phone_numbers) {
        foreach my $a (@ARGV) {
            push @keys, $key if %$phone_numbers{$key} =~ $a;
        }
    }
}
my @uniq_keys = uniq sort @keys;

foreach my $key (@uniq_keys) {
    my $phone_number = %$phone_numbers{$key};
    $mech->get('https://mypage.bmobile.ne.jp/checkout/status?wicket:interface=:1:ddc::IOnChangeListener::&ddc=' . $key) or die;
    my $result_usage = $scraper_usage->scrape($mech->content);
    my $usage = $result_usage->{text};
    my $result_limit = $scraper_limit->scrape($mech->content);
    my $limit = $result_limit->{text};
    my $result_period = $scraper_period->scrape($mech->content);
    my $period = $result_period->{text};
    $mech->get('https://mypage.bmobile.ne.jp/planchange/capsetting_change.html?cmd=https://mypage.bmobile.ne.jp/checkout/status&phoneNumber=' . $phone_number) or die;
    my $result_charge = $scraper_charge->scrape($mech->content);
    my ($charge) = $result_charge->{text} =~ /(（.*）)/;

    print $$, ":", $dt->strftime('%Y%m%d:%H%M%S.%3N'), "\t", $phone_number, "\t", $usage, "\t", substr($limit, 0, -2), "\t", $charge, "\t", $period, "\n";
    $mech->get("http://maker.ifttt.com/trigger/" . $event . "/with/key/" . $secret_key . "?value1=" . $phone_number . "&value2=" . $usage . "MB / " . $limit . "&value3=" . $charge . $period)
        if ($event ne '') or die;
}
