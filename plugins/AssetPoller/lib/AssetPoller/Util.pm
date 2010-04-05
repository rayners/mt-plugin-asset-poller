
package AssetPoller::Util;

use strict;
use warnings;

sub path_to_blog {
  my $class = shift;

  require MT::Blog;
  my $blog_iter = MT::Blog->load_iter();

  my $p = MT->component('assetpoller');

  my $blog_to_path = {};
  while (my $blog = $blog_iter->()) {
    my $directory = $p->get_config_value('directory', 'blog:' . $blog->id);
    $blog_to_path->{$blog->id} = $directory if $directory;
  }

  return $blog_to_path;
}

1;
