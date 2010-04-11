
package AssetPoller::Tasks;

use strict;
use warnings;
use File::Basename;
use File::Spec;
use File::Copy;

sub poll_directory {
    my $task = shift;

    my $p = $task->{plugin};

    # get the hash
    #     path_to_check => blog_id

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

            require MT::Asset;

            # skip if there's already an asset for this filename
            next
                if MT::Asset->exist(
                        { blog_id => $blog->id, file_name => $f } );

            # turn the file into an asset
            my $asset_pkg = MT::Asset->handler_for_file($f);

            require File::Basename;
            my $ext
                = ( File::Basename::fileparse( $file, qr/[A-Za-z0-9]+$/ ) )
                [2];
            my $asset = $asset_pkg->new();
            $asset->blog_id( $blog->id );
            $asset->label($f);
            $asset->file_name($f);
            $asset->file_ext($ext);
            $asset->file_path($file);
            $asset->url('');
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

        }

        closedir(ASSET_DIR);
    }

}

1;
