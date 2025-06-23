#!/usr/bin/perl
use strict;
use Web::Scraper;
use WWW::Mechanize;
use Number::Format qw(:subs);
use DateTime;
use List::MoreUtils qw(uniq);
use utf8;
use LWP::UserAgent;
use JSON;
binmode STDOUT, ':utf8';

# bmobile credentials
my $bmobile_user_id = 'User ID for mypage.bmobile.ne.jp';
my $bmobile_passwd = 'Password for mypage.bmobile.ne.jp';

# LINE Messaging API endpoint
my $url = 'https://api.line.me/v2/bot/message/push';

# LINE Channel Access Token
my $channel_access_token = 'LINE channel access token';

# LINE Group ID
my $line_group_id = 'LINE group ID';

my $dt = DateTime->now(time_zone => 'local');

my $mech = WWW::Mechanize->new();
$mech->get('https://mypage.bmobile.ne.jp/') or die;
$mech->submit_form(
    fields => {
        'josso_username' => $bmobile_user_id,
        'josso_password' => $bmobile_passwd,
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

my $message_text = "";
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

    $message_text .= "電話番号:" . $phone_number . "\n" . "使用量" . $usage . "MB / " . $limit . "\n" . "期間: " . $charge . $period . "\n\n";
}
$message_text = substr($message_text, 0, -2);

# Request payload
my $post_data = {
	to => $line_group_id,
	messages => [
	{
		type => 'text',
		text => $message_text,
	}
	],
};

# Initialize HTTP client
my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new(POST => $url);
$req->header('Content-Type' => 'application/json');
$req->header('Authorization' => "Bearer $channel_access_token");
$req->content(encode_json($post_data));

# Send request
my $res = $ua->request($req);

# Output execution result to STDERR
if ($res->is_success) {
	print STDERR "[INFO] Message sent successfully: ", $res->decoded_content, "\n";
} else {
	print STDERR "[ERROR] Failed to send message: ", $res->status_line, "\n";
	print STDERR "[ERROR] Response body: ", $res->decoded_content, "\n";
}
