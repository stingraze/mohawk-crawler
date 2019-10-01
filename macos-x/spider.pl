#!C:/Perl/bin/perl
#COPYRIGHT Ppctweakies 2003-2019
#Updated version (10/1/2019)
use Getopt::Std;
use vars qw($opt_i $opt_r);

use Encode::Guess qw/ euc-jp shiftjis utf8 7bit-jis /;

use Encode qw/ from_to /;
use Fcntl ':flock'; 

require WWW::RobotRules;
#use Net::SSL;
require LWP::UserAgent;

$| = 1; # Disable STDOUT buffering

my $config_file = "spider.conf";
my $keywords_regexp    = "<meta[^>]+name\s*\=\s*\"keywords\"[^>]+content\s*\=\s*\"([^\">]*)";
my $description_regexp = "<meta[^>]+name\s*\=\s*\"description\"[^>]+content\s*\=\s*\"([^\">]*)";
my $title_regex = "<title\>(.*?)\<\/title>";

#============================================
# DEFAULT CONFIG SETTINGS
#============================================
my $seeds_file  = "seeds.txt";
my $db_file     = "spider_#.dat";
my $db_layout   = "##URL##\t##KEYWORDS##\t##DESCRIPTION##\t##TITLE##\n";
my $max_description_length = 197;
my $max_keywords_length    = 800;
my $generate_keywords      = 1;
my $domain_max_timeout     = 1;

my $guess_encoding_problems     = 1;
my $encoding_problems_threshold = 0.2;

my $max_iterations = 4;
my $max_db_size    = 100000;

my @exclude_url_rules = ();
my @include_url_rules = ('^(http:\/\/www\.|https:\/\/www\.|http:\/\/|https:\/\/)?[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?$');
my @exclude_content_types_rules = ();
my @include_content_types_rules = ('text\/html', 'text\/plain');
my $page_max_size = 200000;
my $ignore_robot_rules = 1;

my $fetch_timeout = 3;
my $user_agent = "Mohawk Crawler - Mozilla Compatible";
my $max_redirects = 7;
my $fetch_pause = 3;

my $use_proxy = 0;
my $proxy_url = 'http://127.0.0.1:8080';

#============================================

# Read configuration file
open (CONFIG, $config_file) or die "Unable to open configuration file: $config_file.";
eval(join ('', <CONFIG>));
close (CONFIG);

################################
my $db_file_index = 1;
my $created_record_per_file = 0;
my @output_files = ();
################################

# Init RobotRules parser
my $robotsrules = new WWW::RobotRules($user_agent);

# Stores the contents of robots.txt files of any host
my %robots = ();

# Initialize the URL queue from the seeds file
my @url_queue = ();
open (SEEDS, $seeds_file) or die "Unable to open $seeds_file.";
foreach(<SEEDS>){
	chomp;
	push @url_queue, $_;
}
close SEEDS;

# Set of the already known urls
my %known_urls = map {$_ => 1} @url_queue;

# Initialize the URL queue for next step
my @next_url_queue = ();

# Value of current iteration
my $iteration = 1;
my $downloaded_pages = 0;
my $downloaded_bytes = 0;
my $created_records  = 0;
my $processed_this_iteration  = 0;

my $output_file_name = $db_file;
$output_file_name =~ s/#/$db_file_index/;

print "Content-type: text/plain; charset=s-jis\n\n";
open (DB, ">>", $output_file_name)  or die "Unable to open $output_file_name.";
push @output_files, $output_file_name;
flock(DB,LOCK_EX);

while ($iteration <= $max_iterations){
	$processed_this_iteration  = 0;
	
	print "-------------------------------------------------------------\n";
	print "Iteration number $iteration started.\n";
	print "Number of pages to fetch: ".($#url_queue + 1)."\n";
	print "-------------------------------------------------------------\n";
	
	# loop on current queue
	foreach my $url (@url_queue){
		$processed_this_iteration ++;
		
		$url = normalize_url($url);
		
		if(should_process_url($url)){
			
			# Check for robot rules if check enabled
			if ($ignore_robot_rules || is_robot_allowed($url)){

				my $page_text = get_page($url);
				
				if ($page_text){
					$page_text = normalize_page($page_text);
					
					if ($guess_encoding_problems && has_encoding_problems($page_text)){
						print "----> Page has unsupported character encoding.\n";
						next;
					}
					

					
					# get keywords and description
					my $description = get_description($page_text);
					# Added on 04/05/16: get html snippet when meta description does not exist
					if ($description eq '') {
						$description = get_page_summary($page_text, $max_description_length);
						$description_length = length($description);
						if ($description_length > 197){
						$description = "$description...";
						}
					}					
					
					my $guess = Encode::Guess::guess_encoding($description);
					if (ref $guess && $guess->name ne 'utf8') {
  					Encode::from_to($description, $guess->name, 'utf8');
					}


								
					

					#Figure out the encoding 
					my $keywords    = get_keywords($page_text);
					
					my $guess1 = Encode::Guess::guess_encoding($keywords);
					if (ref $guess1 && $guess1->name ne 'utf8') {
  					Encode::from_to($keywords, $guess1->name, 'utf8');
					}

					# get keywords and description
					my $title = get_title($page_text);
				
					if ($description || $keywords || $title) {
						
						
						if ( $created_record_per_file == $lines_per_file ) {
							
							flock(DB,LOCK_UN);
							close DB;
							$created_record_per_file = 0;
							$db_file_index++;
							
							my $output_file_name = $db_file;
							$output_file_name =~ s/#/$db_file_index/;
							
							print "Content-type: text/plain; charset=s-jis\n\n";
							open (DB, ">>", $output_file_name)  or die "Unable to open $output_file_name.";
							push @output_files, $output_file_name;
							flock(DB,LOCK_EX);
						}
						
						print DB get_db_record($url, $keywords, $description, $title);
						$created_records++;
						$created_record_per_file++;
						flock(DB,LOCK_UN);
						# Finish if max size reached
						if ($created_records == $max_db_size){
							print "-------------------------------------------------------------\n";
							print "Maximum database size reached ($max_db_size).\n";
							print_iteration_stats();
							print "Process completed.";
							close DB;
							exit (0);
						}
					}
					
					# If we have a next iteration then process also anchors
					if ($iteration < $max_iterations) {
						my @anchors;
						my @frames;
						my @imagemaps;
		   			(@anchors)    = $page_text =~ m/<a[^>]*href\s*=\s*["']([^"'>]*)"/gsxi;
		   			(@frames)     = $page_text =~ m/<i?frame[^>]*src\s*=\s*["']([^"'>]*)"/gsxi;
		   			(@imagemaps)  = $page_text =~ m/<area[^>]*href\s*=\s*["']([^"'>]*)"/gsxi;
						my @all_links = ();
						push @all_links, @anchors;
						push @all_links, @frames;
						push @all_links, @all_links;
						my $added_pages = 0;
						foreach my $anchor (@anchors){
			      	my $new_url = get_fully_quialified_url($url, $anchor);
			      	unless (defined $known_urls{$new_url}) {
			      		push @next_url_queue, $new_url;
			      		$known_urls{$new_url} = 1;
			      		$added_pages++;
			      	}
						}
						print "----> New pages found               : $added_pages\n";
					}
				}
				print "----> Remaining pages for iteration : ". ($#url_queue + 1 - $processed_this_iteration) ."\n\n";
				if ($fetch_pause) {sleep ($fetch_pause);}
			}
		}
	}
	@url_queue = ();
	push @url_queue, @next_url_queue;
	@next_url_queue = ();
	print_iteration_stats();
	$iteration++;
	
}

print "Process completed.";
close DB;



my $dbfile   = "spider.dat";
my $keywords = "keywords.dat";
my $urls     = "urls.dat";
my $descr    = "descriptions.dat";
my $title	 = "title.dat";

my @lines;
foreach $output_file (@output_files) {
	
	open (I, $output_file) or die "Unable to open: $output_file";
	my @lines_in_file = <I>;
	close I;
	
	push @lines, @lines_in_file;
}

open (K, ">$keywords")   or die "Unable to open: $keywords";
open (U, ">$urls")       or die "Unable to open: $urls";
open (D, ">$descr")      or die "Unable to open: $descr";
open (T, ">title")		 or die "Unable to open: $title";
foreach (@lines){
	chomp;
	my ($u, $k, $d, $t) = split(/¥t/, $_, 4);
	print K "$k\n";
	print U "$u\n";
	print D "$d\n";
	print T "$t\n";
}
close K;
close U;
close D;
close T;

@lines = reverse(@lines);
open (K, ">rev_$keywords")   or die "Unable to open: rev_$keywords";
open (U, ">rev_$urls")       or die "Unable to open: rev_$urls";
open (D, ">rev_$descr")      or die "Unable to open: rev_$descr";
open (T, ">rev_$title")	 or die "Unable to open: rev_$title";
foreach (@lines){
	chomp;
	my ($u, $k, $d, $t) = split(/¥t/, $_, 4);
	print K "$k\n";
	print U "$u\n";
	print D "$d\n";
	print T "$t\n";
}
close K;
close U;
close D;
close T;

#Sort Alphabetically A-Z
@lines = sort(@lines);
open (K, ">sort_$keywords")   or die "Unable to open: rev_$keywords";
open (U, ">sort_$urls")       or die "Unable to open: rev_$urls";
open (D, ">sort_$descr")      or die "Unable to open: rev_$descr";
open (T, ">sort_$title")	  or die "Unable to open: rev_title";
foreach (@lines){
	chomp;
	my ($u, $k, $d, $t) = split(/¥t/, $_, 4);
	print K "$k\n";
	print U "$u\n";
	print D "$d\n";
	print T "$t\n";
}
close K;
close U;
close D;
close T;

#Sort Alphabetically Z-A
@lines = reverse sort(@lines);
open (K, ">revsort_$keywords")   or die "Unable to open: rev_$keywords";
open (U, ">revsort_$urls")       or die "Unable to open: rev_$urls";
open (D, ">revsort_$descr")      or die "Unable to open: rev_$descr";
open (T, ">revsort_$title")     or die "Unable to open: rev_title";
foreach (@lines){
	chomp;
	my ($u, $k, $d, $t) = split(/¥t/, $_, 4);
	print K "$k\n";
	print U "$u\n";
	print D "$d\n";
	print T "$t\n";
}
close K;
close U;
close D; 
close T;

exit (0);

##############################################
# Print last iteration statistics
##############################################
sub print_iteration_stats {
	print "-------------------------------------------------------------\n";
	print "Iteration number $iteration completed.\n";
	print "Total pages downloaded : $downloaded_pages\n";
	print "Total bytes downloaded : $downloaded_bytes\n";
	print "Total records created  : $created_records\n";
	print "-------------------------------------------------------------\n\n";
}

##############################################
# Check if a given url should be processed
# according to include/exclude rules
##############################################
sub should_process_url {
	my $url = shift;
	
	if ($domain_max_timeout){
		my ($protocol, $rest) = $url =~ m|^([^:/]*):(.*)$|;
		my ($server_host, $port, $document) = $rest =~ m|^//([^:/]*):*([0-9]*)/*([^:]*)$|;
		$domain_times{$iteration}{$server_host} ||= time();
		return 0 if (time() - $domain_times{$iteration}{$server_host} > $domain_max_timeout);
	}
	
	foreach my $exclude_rule (@exclude_url_rules){
		return 0 if ($url =~ /$exclude_rule/);
	}
	foreach my $include_rule (@include_url_rules){
		return 1 if ($url =~ /$include_rule/);
	}
	
	return 0;
}

##############################################
# Check if a given url should be processed
# according to content type
##############################################
sub check_content_type {
	my $content_type = shift;
	
	foreach my $exclude_content_types_rule (@exclude_content_types_rules){
		return 0 if ($content_type =~ /$exclude_content_types_rule/);
	}
	foreach my $include_content_types_rule (@include_content_types_rules){
		return 1 if ($content_type =~ /$include_content_types_rule/);
	}
	
	return 0;	
}

##############################################
# Check if a given url should be processed
# according to robot rules
##############################################
sub is_robot_allowed {

	my $url = shift;
	
	my ($protocol, $rest) = $url =~ m|^([^:/]*):(.*)$|;
  my ($server_host, $port, $document) = $rest =~ m|^//([^:/]*):*([0-9]*)/*([^:]*)$|;  
  if (!$port) {$port = 80;}
  
  my $key = "$server_host:$port";
  
  # If we haven't yet downloaded robot.txt from this host, donload it now
  unless (defined $robots{$key}){load_robot_rules($server_host, $port);}
  
  # Now check rules
  if ($robots{$key}){
		$robotsrules->parse($url, $robots{$key});  	
		return $robotsrules->allowed($url);
  }
  else {
  	return 1;
  }
}

##############################################
# Load robot.txt rules. Gets an internal
# representation of disallow rules that apply to us
##############################################
sub load_robot_rules {
	
	my $host = shift;
	my $port = shift;

  my $key = "$host:$port";
	
	my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0});
	setup_ua($ua);
	
	my $url = "http://$host:$port/robots.txt";
	
	print "--> Fetching: robots.txt for: http://".$host.":".$port."...";
	my $response = $ua->get($url);
	if ($response->is_success){
		$downloaded_bytes += length($response->content);
		$robots{$key} = $response->content;
		print "OK.\n";
	}
	else {
		$robots{$key} = '';
		print "Failed, ignoring it. ".$response->status_line."\n";
	}	
}

##############################################
# Gets a page
##############################################
sub get_page {
	my $url = shift;
	
	my $ua = LWP::UserAgent->new;
	setup_ua($ua);

	print "--> Fetching: $url......";
	my $response = $ua->get($url);
		
	if ($response->is_success){
		unless(check_content_type($response->header('content-type'))){
			print "Excluded because of content type (".$response->header('content-type').") .\n";
			return "";
		};
		print "OK.\n";
		$downloaded_pages++;
		$downloaded_bytes += length($response->content);
		return $response->content;
	}
	else {
		print "Error. ".$response->status_line."\n";
		return "";
	}
}

##############################################
# Setup user agent
##############################################
sub setup_ua {
	my $ua = shift;
	$ua->agent($user_agent);
	$ua->timeout($fetch_timeout);
	$ua->max_redirect($max_redirects);
	$ua->max_size($page_max_size) if (defined $page_max_size);
	$ua->proxy('http', $proxy_url) if ($use_proxy);
}

##############################################
# Normalize page content for processing
##############################################
sub normalize_page (){
	my $page_text = shift;
	$page_text =~ s/[\r\n]/ /gsx;
	$page_text =~ s/\s+/ /gsx;
	$page_text =~ s|<!--[^>]*-->||gsx;
	return $page_text;
}

##############################################
# Normalize url. If there is no path, be sure to have a / at the end
##############################################
sub normalize_url (){
	my $url = shift;
	if ($url =~ /^http\:\/\/[^\/]+$/i){$url .= '/';}
	return $url;
}


##############################################
# Build a fully specified URL.
##############################################
sub get_fully_quialified_url {

	my ($thisURL, $anchor) = @_;
	my ($has_proto, $has_lead_slash, $currprot, $currhost, $newURL);

	# Strip anything following a number sign '#', because its
	# just a reference to a position within a page.
	$anchor =~ s|^.*#[^#]*$|$1|;

	# Examine anchor to see what parts of the URL are specified.
	$has_proto = 0;
	$has_lead_slash=0;
	$has_proto = 1 if($anchor =~ m|^[^/:]+:|);
	$has_lead_slash = 1 if ($anchor =~ m|^/|);

	if($has_proto == 1){
	   # If protocol specified, assume anchor is fully qualified.
	   $newURL = $anchor;
	}
	elsif($has_lead_slash == 1){
   # If document has a leading slash, it just needs protocol and host.
   ($currprot, $currhost) = $thisURL =~ m|^([^:/]*):/+([^:/]*)|;
   $newURL = $currprot . "://" . $currhost . $anchor;
	}
	else{
	   ($newURL) = $thisURL =~ m|^(.*)/[^/]*$|;
	   $newURL .= "/" if (! ($newURL =~ m|/$|));
	   $newURL .= $anchor;
	
	}
	return $newURL;
}

######################################################
# Get description from HTML comtent
######################################################
sub get_description {
	my $page_text = shift;
	my $description = '';
	if ($page_text =~ m/$description_regexp/gsxi){$description = $1;}

	if (length ($description) > $max_description_length){
		($description) = $description =~ /^(.{0,$max_description_length})\s/gsx;
	}
	
	return $description;
}

######################################################
# Get title from HTML comtent
######################################################
sub get_title {
	my $page_text = shift;
	my $title = '';
	if ($page_text =~ m/$title_regex/gsxi){$title = $1;}
	return $title;
}

######################################################
# Get keywords from HTML content
######################################################
sub get_keywords {
	my $page_text = shift;
	my $keywords = '';
	if ($page_text =~ m/$keywords_regexp/gsxi){$keywords = $1;}

	if (length ($keywords) > $max_keywords_length){
		($keywords) = $keywords =~ /^(.{0,$max_keywords_length})\s/gsx;
	}

	if (!$keywords && $generate_keywords){
		$keywords = generate_keywords($page_text);
	}
	
	return $keywords;
}

######################################################
# Generate a set of keywords from html content
######################################################
sub generate_keywords {
	
	my $page_text = shift;
	my @keywords;
		
	# Remove all tags and get lower case
	$page_text = extract_text($page_text);
	$page_text = lc($page_text);
	
	# Take all words longer than 4 chars
	(@keywords) = $page_text =~ /\s([a-zA-Z0-9\-\@]{5,})\s/gsx;

	# Count word frequency
	my %tmp = ();
	foreach my $word (@keywords){
		if (defined $tmp{$word}) {$tmp{$word} += 1;}
		else {$tmp{$word} = 1;}
	}

	# Remove duplicates
	my %keyword_hash = map {$_ => 1} @keywords;
	@keywords = keys %keyword_hash;

	# Sort according to frequency
	my @out = sort { $tmp{$b} <=> $tmp{$a} } @keywords;

	my $keywords = join (', ', @out);

	if (length ($keywords) > $max_keywords_length){
		($keywords) = $keywords =~ /^(.{0,$max_keywords_length})\s/gsx;
	}
	
	return $keywords;
}

######################################################
# Generate record to be written to DB
######################################################
sub get_db_record {
	my $url         = shift;
	my $keywords    = shift;
	my $description = shift;
	my $title = shift;

	my $record = $db_layout;
	$record =~ s/##KEYWORDS##/$keywords/;
	$record =~ s/##DESCRIPTION##/$description/;
	$record =~ s/##URL##/$url/;
	$record =~ s/##TITLE##/$title/;

	return $record;
}

######################################################
# Checks if a page has too many unrecognized characters
######################################################
sub has_encoding_problems {
		my $page_text = shift;
	
		$page_text = extract_text($page_text);
		$page_text = lc ($page_text);
		
		# Remove tags and whitespaces, html escape chars
		$page_text =~ s/\&.{1,5}\;//gsx;
		$page_text =~ s/\s//gsx;
		
		my $original_length = length ($page_text);
		if (!$original_length) {return 0;}
		
		# Remove all good characters
		$page_text =~ s/[a-z0-9]//gsx;
		
		my $strange_chars = length ($page_text);
		
		if ($strange_chars/$original_length > $encoding_problems_threshold){
			return 1;
		}
		else {
			return 0;
		}
}

######################################################
# Remove all tage
######################################################
sub extract_text {
	my $page_text = shift;

	$page_text =~ s/<script.*?\/script>//gsxi;
	$page_text =~ s/<style.*?\/style>//gsxi;
	$page_text =~ s/<[^>]*>//gsx;
	
	return $page_text;
}

###############################################################
# Get the page summary - remove irrelevant tags and contents
###############################################################
sub get_page_summary {
	my $content = shift;	
	my $maxdesclength = shift;		

	# Remove all irrelevant html tag CONTENT	
	$content =~ s/<!--.*?-->//gsxi;	
	$content =~ s/<script.*?\/script>//gsxi;	
	$content =~ s/<noscript.*?\/noscript>//gsxi;		
	$content =~ s/<table.*?\/table>//gsxi;		
	$content =~ s/<applet.*?\/applet>//gsxi;	
	$content =~ s/<embed.*?\/embed>//gsxi;		
	$content =~ s/<object.*?\/object>//gsxi;	
	$content =~ s/<param.*?\/param>//gsxi;			
	$content =~ s/<header.*?\/header>//gsxi;	
	$content =~ s/<footer.*?\/footer>//gsxi;		
	$content =~ s/<style.*?\/style>//gsxi;	
	$content =~ s/<dialog.*?\/dialog>//gsxi;	
	$content =~ s/<menu.*?\/menu>//gsxi;	
	$content =~ s/<menuitem.*?\/menuitem>//gsxi;	
	$content =~ s/<audio.*?\/audio>//gsxi;	
	$content =~ s/<source.*?\/source>//gsxi;	
	$content =~ s/<track.*?\/track>//gsxi;	
	$content =~ s/<video.*?\/video>//gsxi;	
	$content =~ s/<img.*?\/img>//gsxi;	
	$content =~ s/<map.*?\/map>//gsxi;	
	$content =~ s/<area.*?\/area>//gsxi;	
	$content =~ s/<canvas.*?\/canvas>//gsxi;	
	$content =~ s/<figcaption.*?\/figcaption>//gsxi;
	$content =~ s/<figure.*?\/figure>//gsxi;		
	$content =~ s/<form.*?\/form>//gsxi;	
	$content =~ s/<input.*?\/input>//gsxi;	
	$content =~ s/<textarea.*?\/textarea>//gsxi;	
	$content =~ s/<button.*?\/button>//gsxi;	
	$content =~ s/<video.*?\/video>//gsxi;	
	$content =~ s/<select.*?\/select>//gsxi;	
	$content =~ s/<optgroup.*?\/optgroup>//gsxi;	
	$content =~ s/<option.*?\/option>//gsxi;	
	$content =~ s/<label.*?\/label>//gsxi;	
	$content =~ s/<fieldset.*?\/fieldset>//gsxi;
	$content =~ s/<legend.*?\/legend>//gsxi;			
	$content =~ s/<datalist.*?\/datalist>//gsxi;	
	$content =~ s/<keygen.*?\/keygen>//gsxi;
	$content =~ s/<output.*?\/output>//gsxi;		
	$content =~ s/<kbd.*?\/kbd>//gsxi;			
	$content =~ s/<q.*?\/q>//gsxi;		
	$content =~ s/<blockquote.*?\/blockquote>//gsxi;	
	$content =~ s/<s.*?\/s>//gsxi;
	$content =~ s/<samp.*?\/samp>//gsxi;	
	
	# Remove all irrelevant html start tags
	$content =~ s/<(font|br|center|!DOCTYPE|html|head|meta|base|title|basefont|body|style|abbr|address|b|bdi|bdo|big|blockquote|defines|cite|code|del|dfn|em|font|i|ins|kbd).*?>//gsxi;
	$content =~ s/<(mark|meter|pre|progress|q|rp|ruby|s|rt|samp|small|strike|strong|sub|sup|time|tt|u|var|wbr|div|span|main|section|article|aside|details|summary|dir).*?>//gsxi;
	$content =~ s/<(a|link|nav|frame|frameset|noframes|iframe|acronym|abbr|address|b|bdi|bdo|big|code|del|dfn|font|i|ins|mark|meter|progress|rp|rt|ruby|small|strong|sub).*?>//gsxi;
	$content =~ s/<(sup|time|tt|u|var|wbr|br|hr|p|textarea|a|ul|ol|li||dl|dt|dd|article|aside|summary|h1|h2|h3|h4|h5|h6).*?>//gsxi;			

	# Remove all irrelevant html end tags
	$content =~ s/<\/(font|br|center|!DOCTYPE|html|head|meta|base|title|basefont|body|style|abbr|address|b|bdi|bdo|big|blockquote|defines|cite|code|del|dfn|em|font|i|ins)>//gsxi;
	$content =~ s/<\/(kbd|mark|meter|pre|progress|q|rp|ruby|s|rt|samp|small|strike|strong|sub|sup|time|tt|u|var|wbr|div|span|main|section|article|aside|details|summary|dl)>//gsxi;
	$content =~ s/<\/(dt|dd|a|link|nav|frame|frameset|noframes|iframe|acronym|abbr|address|b|bdi|bdo|big|code|del|dfn|font|i|ins|mark|rp|rt|ruby|small|strong|sub|sup|time)>//gsxi;
    $content =~ s/<\/(meter|progress|tt|u|var|wbr|br|hr|p|textarea|a|ul|ol|li|article|aside|summary|h1|h2|h3|h4|h5|h6)>//gsxi;

	# Remove all other irrelevant html tags left
	$content =~ s/<.*?>//gsxi;		
	$content =~ s/<.*?\/>//gsxi;	
	
	# Remove multi-spaces	
	$content =~ s/([\s]+)/ /sg;	
	
	# Truncate the summary to the configured length
	$content = substr( $content, 0, $maxdesclength );
	return $content;
}