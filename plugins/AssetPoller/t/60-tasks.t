use lib qw(t/lib lib extlib);

use strict;
use warnings;

use MT::Test qw( :db :data );
use Test::More tests => 19;

require MT::Blog;
my $blog = MT::Blog->load(1);

my $p = MT->component('assetpoller');

# first try it with the non-destructive (but non-default!) option
$p->set_config_value( 'remove_files', 0, 'blog:1' );

require MT::Asset;
ok( !MT::Asset->exist( { blog_id => 1, file_name => 'test.txt' } ),
    "Asset doesn't exist yet" );
ok( -f 'plugins/AssetPoller/t/incoming/test.txt', "Origin file exists" );
ok( !-f 't/site/assets/test.txt',                 "File doesn't exist yet" );

_run_rpt();

ok( !MT::Asset->exist( { blog_id => 1, file_name => 'test.txt' } ),
    "Asset still doesn't exist" );
ok( !-f 't/site/assets/test.txt', "File still doesn't exist" );

$p->set_config_value( 'directory', 'plugins/AssetPoller/t/incoming',
    'blog:1' );

require MT::Session;
MT::Session->remove( { id => 'Task:asset_poller_poll_directory' } );

_run_rpt();

ok( -f 'plugins/AssetPoller/t/incoming/test.txt',
    "Origin file was not removed" );
ok( MT::Asset->exist( { blog_id => 1, file_name => 'test.txt' } ),
    "Asset exists now" );
ok( -f 't/site/assets/test.txt', "File exists now" );

my $asset = MT::Asset->load( { blog_id => 1, file_name => 'test.txt' } );

is( $asset->column('file_path'),
    '%r/assets/test.txt', "file_path column has the correct % shortcut" );
is( $asset->file_path, "t/site/assets/test.txt",
    "calculated file_path is correct" );

is( $asset->column('url'), '%r/assets/test.txt',
    'url column has the correct % shortcut' );
is( $asset->url,
    'http://narnia.na/nana/assets/test.txt',
    "calculated url is correct"
);

MT::Session->remove( { id => 'Task:asset_poller_poll_directory' } );

_run_rpt();

ok( -f 'plugins/AssetPoller/t/incoming/test.txt',
    "Origin file was still not removed"
);
is( MT::Asset->count( { blog_id => 1, file_name => 'test.txt' } ),
    1, "Only one asset associated with test.txt" );

# just in case
$asset->refresh;

$asset->remove;

ok( !MT::Asset->exist( { blog_id => 1, file_name => 'test.txt' } ),
    "Asset no longer exists" );
ok( !-f 't/site/assets/test.txt', "Asset file was removed" );

$p->set_config_value( 'remove_files', 1, 'blog:1' );
MT::Session->remove( { id => 'Task:asset_poller_poll_directory' } );

_run_rpt();

ok( !-f 'plugins/AssetPoller/t/incoming/test.txt',
    "Origin file was removed" );
ok( MT::Asset->exist( { blog_id => 1, file_name => 'test.txt' } ),
    "Asset exists again" );
ok( -f 't/site/assets/test.txt', "File exists again" );

1;

