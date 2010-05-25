package AssetPoller::Tasks;

use strict;
use warnings;
use File::Basename;
use File::Spec;
use File::Copy;

use MT::Util qw(ts2epoch epoch2ts);
use MT::Asset;

sub poll_directory {
    my $task = shift;

    my $p = $task->{plugin};

    require AssetPoller::Util;
    my $path_to_blog = AssetPoller::Util->path_to_blog || {};

    require MT;
    my $mt_dir = MT->instance->{mt_dir};

PATH:
    foreach my $k ( keys %$path_to_blog ) {

        my $blog_id = $k;
        my $blog    = MT::Blog->load($blog_id) or next PATH;
        my $fmgr    = $blog->file_mgr;

        my $path_tmpl = $p->get_config_value( 'destination_path_template',
            'blog:' . $blog_id );
        my $remove_files
            = $p->get_config_value( 'remove_files', 'blog:' . $blog_id );
        my $default_tags
            = $p->get_config_value( 'default_tags', 'blog:' . $blog_id );

        my @tags = split( /\s*,\s*/, $default_tags );

        # directory is relative to MT dir
        # unless absolute
        my $path = $path_to_blog->{$k};
        unless ( File::Spec->file_name_is_absolute($path) ) {
            $path = File::Spec->catdir( $mt_dir, $path );
        }

        # grab the files from the dir
        opendir( ASSET_DIR, $path )
            or next PATH;

        my @files = readdir(ASSET_DIR);

    FILE:
        foreach my $f (@files) {
            next FILE if ( $f =~ /^\./ );
            my $file = File::Spec->catfile( $path, $f );
            next FILE unless ( -f $file );
            
            # Grab the file filters, so that the polled directory contents can
            # be properly filtered to find only the desired files.
            my $file_filter = $p->get_config_value('file_filter', 'blog:'.$blog_id);
            if ($file_filter) {
                # Remove any space before or after the comma separator, and build an array.
                my @file_filters = split(/\s*,\s*/, $file_filter);
                my $skip;
                foreach my $filter (@file_filters) {
                    # Use the $skip "flag" to indicate whether a filter matched.
                    # If the filter matches the filename, mark it to be skipped.
                    # (This gives the chance for all filters to run before
                    # deciding if it should be skipped.) If it's not a match,
                    # pass the previously-set $skip so that the previous state
                    # is still saved.
                    $skip = ( $f =~ /$filter/i ) ? 1 : $skip;
                }
                next unless $skip;
            }

            my $asset;
            my $asset_pkg;

            # Does the user want to import files that have been updated?
            my $import_updated = $p->get_config_value('import_updated_files', 'blog:'.$blog_id);
            if ($import_updated) {
                # If any newer files are found, they should be imported.
                # Grab the epoch time for the new file.
                my $file_stamp = (stat($file))[9];

                # Grab the existing asset, and its time.
                # Use class "*" so that images, files, and any other class of object are returned.
                $asset = MT->model('asset')->load({ blog_id => $blog_id, class => '*', file_name => $f });
                if ($asset) {
                    my $existing_stamp = ts2epoch($blog, $asset->modified_on);

                    # Only proceed if the file is newer than the asset.
                    next if ($file_stamp <= $existing_stamp);

                    # The file is newer than the existing asset. So, just import it.
                    $asset->modified_on( epoch2ts($blog, $file_stamp) );
                }
                else {
                    # The file hasn't been imported yet, so create a new asset
                    $asset_pkg = MT::Asset->handler_for_file($f);
                    $asset = $asset_pkg->new();
                }
            }
            else {
                # Don't import newer files, just ignore them.
                # Use class "*" so that images, files, and any other class of object are returned.
                next
                    if MT::Asset->exist(
                            { blog_id => $blog->id, class => '*', file_name => $f } );

                # But we do want to import any new asset.
                $asset_pkg = MT::Asset->handler_for_file($f);
                $asset = $asset_pkg->new();
            }

            # turn the file into an asset
            require File::Basename;
            my $ext
                = ( File::Basename::fileparse( $file, qr/[A-Za-z0-9]+$/ ) )
                [2];
            $asset->blog_id( $blog->id );
            $asset->label($f);
            $asset->file_name($f);
            $asset->file_ext($ext);
            $asset->file_path($file);
            $asset->url('');
            $asset->tags(@tags);
            $asset->save or die $asset->errstr;

            # move the file into the directory dictacted by the template

            require MT::Template::Context;
            my $ctx = MT::Template::Context->new;
            $ctx->stash( 'asset',   $asset );
            $ctx->stash( 'blog',    $blog );
            $ctx->stash( 'blog_id', $blog->id );

            require MT::Builder;
            my $builder = MT::Builder->new;
            my $tokens = $builder->compile( $ctx, $path_tmpl );
            my $dest_path;
            defined( $dest_path = $builder->build( $ctx, $tokens ) )
                or die $builder->errstr;
            $dest_path =~ s!/$!!
                unless $dest_path eq
                    '/';    ## OS X doesn't like / at the end in mkdir().

            unless ( $dest_path =~ /^(?:\/|\%[ras])/ ) {
                $dest_path = '%r/' . $dest_path;
            }
            my $dest_file = File::Spec->catfile( $dest_path, $f );
            my $dest_url = $dest_file;
            $asset->clear_cache;
            $dest_file = $asset->file_path($dest_file);
            $asset->url($dest_url);

            $dest_path = dirname($dest_file);
            unless ( $fmgr->exists($dest_path) ) {
                $fmgr->mkpath($dest_path) or die $fmgr->errstr;
            }
            my $meth = ( $remove_files ? 'rename' : 'put' );
            $fmgr->$meth( $file, $dest_file ) or die $fmgr->errstr;
            $asset->save;
            
            MT->log({
                level   => MT->model('log')->INFO(),
                blog_id => $blog_id,
                message => MT->translate(
                    'Asset Poller has imported the file [_1].',
                    $f,
                ),
            });

        }

        closedir(ASSET_DIR);
    }
}

1;
