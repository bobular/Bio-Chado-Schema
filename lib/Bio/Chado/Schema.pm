package Bio::Chado::Schema;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_classes;


# Created by DBIx::Class::Schema::Loader v0.04999_12 @ 2010-01-01 13:09:35
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:GfcGc0XJeU/0mXXXgJb7FQ

=head1 NAME

Bio::Chado::Schema - A standard DBIx::Class layer for the Chado database schema.

=head1 SYNOPSIS

  use Bio::Chado::Schema;

  my $chado = Bio::Chado::Schema->connect( $dsn, $user, $password );

  print "number of rows in feature table: ",
        $chado->resultset('Sequence::Feature')->count,
        "\n";


=head1 DESCRIPTION

This is a standard object-relational mapping layer for use with the
GMOD Chado database schema.  This layer is implemented with
L<DBIx::Class>, generated with the help of the very fine
L<DBIx::Class::Schema::Loader> module.

Chado is an open-source modular database schema for biological data.
It is divided into several notional "modules", which are reflected in
the namespace organization of this package.  Note that modules in the
Chado context refers to sets of tables, they are not modules in the
Perl sense.

To learn how to use this DBIx::Class ORM layer, a good starting
point is the L<DBIx::Class::Manual>.

=head1 CHADO MODULES COVERED BY THIS PACKAGE

L<Bio::Chado::Schema::CellLine>

L<Bio::Chado::Schema::Companalysis>

L<Bio::Chado::Schema::Composite>

L<Bio::Chado::Schema::Contact>

L<Bio::Chado::Schema::Cv>

L<Bio::Chado::Schema::Expression>

L<Bio::Chado::Schema::General>

L<Bio::Chado::Schema::Genetic>

L<Bio::Chado::Schema::Library>

L<Bio::Chado::Schema::Mage>

L<Bio::Chado::Schema::Map>

L<Bio::Chado::Schema::NaturalDiversity>

L<Bio::Chado::Schema::Organism>

L<Bio::Chado::Schema::Phenotype>

L<Bio::Chado::Schema::Phylogeny>

L<Bio::Chado::Schema::Project>

L<Bio::Chado::Schema::Pub>

L<Bio::Chado::Schema::Sequence>

L<Bio::Chado::Schema::Stock>


=head1 CONTRIBUTORS

Aureliano Bombarely, <ab782@cornell.edu>

Naama Menda, <nm249@cornell.edu>

Jonathan "Duke" Leto, <jonathan@leto.net>

=head1 AUTHOR

Robert Buels, <rmb32@cornell.edu>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Boyce Thompson Institute for Plant Research

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


#########################################################################################
##                                                                                     ##
## NOTE: The documentation for this package can be found in Bio/Chado/Schema/Util.pod  ##
##                                                                                     ##
## The reason to put this package in the same file than Schema.pm is because if you    ##
## put non DBIx::Class packages under Schema folder, when Module::Find get all the     ##
## dbix classes to load in the schema, the non dbix classes will return an error       ##
##                                                                                     ##
#########################################################################################

package Bio::Chado::Schema::Util;
use strict;
use Carp::Clan qr/^Bio::Chado::Schema/;


sub create_properties {
    my ($class,  %args) = @_;

    #check for required args
    $args{prop_relation_name} or confess "must provide $_ arg"
      for qw/ row prop_relation_name properties options/;

    my $self  = delete $args{row};
    my $props = delete $args{properties};
    my $opts  = delete $args{options};
    my $prop_relation_name = delete $args{prop_relation_name};

    %args and confess "invalid option(s): ".join(', ', sort keys %args);

    # normalize the props to hashrefs
    foreach (values %$props) {
        $_ = { value => $_ } unless ref eq 'HASH';
    }

    # process opts
    $opts ||= {};
    defined $opts->{cv_name} or confess 'must provide a cv_name in options';
    $opts->{db_name} = 'null'
        unless defined $opts->{db_name};
    $opts->{dbxref_accession_prefix} = 'autocreated:'
        unless defined $opts->{dbxref_accession_prefix};

    my $schema = $self->result_source->schema;

    my $prop_cv = do {
        my $cvrs = $schema->resultset('Cv::Cv');
        my $find_or_create = $opts->{autocreate} ? 'find_or_create' : 'find';
        $cvrs->$find_or_create({ name => $opts->{cv_name}},
                               { key => 'cv_c1' })
            or croak "cv '$opts->{cv_name}' not found and autocreate option not passed, cannot continue";
    };

    my $prop_db; #< set as needed below

    # find/create cvterms and dbxrefs for each of our featureprops,
    # and remember them in %propterms
    my %propterms;
    foreach my $propname (keys %$props) {
        my $existing_cvterm = $propterms{$propname} =
            $prop_cv->find_related('cvterms',
                                   { name => $propname,
                                     is_obsolete => 0,
                                   },
                                   { key => 'cvterm_c1' },
                                  );

        # if there is no existing cvterm for this in the prop table,
        # and we have the autocreate flag set true, then create a
        # cvterm, dbxref, and db for it if necessary
        unless( $existing_cvterm ) {
            $opts->{autocreate}
               or croak "cvterm not found for property '$propname', and autocreate option not passed, cannot continue";

            # look up the db object if we don't already have it, now
            # that we know we need it
            $prop_db ||=
                $self->result_source->schema
                     ->resultset('General::Db')
                     ->find_or_create( { name => $opts->{db_name} },
                                       { key => 'db_c1' }
                                     );

            # find or create the dbxref for this cvterm we are about
            # to create
            my $dbx_acc = $opts->{dbxref_accession_prefix}.$propname;
            my $dbxref =
                $prop_db->search_related( 'dbxrefs',
                                          { accession => $dbx_acc },
                                          { order_by => { -desc => ['version'] } }
                                        )
                                ->first
             || $prop_db->create_related( 'dbxrefs', { accession => $dbx_acc,
                                                               version => 1,
                                                             });

            # look up any definition we might have been given for this
            # propname, so we can insert it if given
            my $def = $opts->{definitions}->{$propname};

            $propterms{$propname} =
                $prop_cv->create_related('cvterms',
                                         { name => $propname,
                                           is_obsolete => 0,
                                           dbxref_id => $dbxref->dbxref_id,
                                           $def ? (definition => $def) : (),
                                         }
                                        );
        }
    }

    my %props;
    while( my ($propname,$propval) = each %$props ) {

        my $data = ref $propval
            ? {%$propval}
            : { value => $propval };

        $data->{type_id} = $propterms{$propname}->cvterm_id;


      # decide whether to skip creating this prop
      my $skip_creation = $opts->{allow_duplicate_values}
            ? 0
            : $self->search_related( $prop_relation_name,
                                     { type_id => $data->{type_id},
                                       value   => $data->{value},
                                     })
                   ->count;


        unless( $skip_creation ) {
            #if rank is defined
          if ($opts->{rank} && defined $opts->{rank} ) {
            my ($existing_prop) = $self->search_related( $prop_relation_name,
                                            {type_id =>$data->{type_id},
                                             rank => $opts->{rank}
                                            });
            warn "Property " .  $existing_prop->value() . "  already exists with rank " . $opts->{rank} . ". skipping! \n" if  defined $existing_prop;
            $data->{rank} = $opts->{rank};

          } else {
            # find highest rank for props of this type
            my $max_rank= $self->search_related( $prop_relation_name,
                                         { type_id =>$data->{type_id} }
                )->get_column('rank')->max;
            $data->{rank} = defined $max_rank ? $max_rank + 1 : 0;

          }
          $props{$propname} = $self->find_or_create_related( $prop_relation_name,
                                           $data
            );
      }
    }
    return \%props;
}

1;

package Bio::Chado::Schema::Test;
use strict;
use warnings;
use Carp::Clan qr/^Bio::Chado::Schema/;
use Bio::Chado::Schema;

=head1 NAME

Bio::Chado::Schema::Test - Library to be used by Bio::Chado::Schema test scripts.

=head1 SYNOPSIS

  use lib qw(t/lib);
  use Bio::Chado::Schema::Test;
  use Test::More;

  my $schema = Bio::Chado::Schema::Test->init_schema();

=head1 DESCRIPTION

This module provides the basic utilities to write tests against Bio::Chado::Schema.

=head1 METHODS

=head2 init_schema

  my $schema = Bio::Chado::Schema::Test->init_schema(
    deploy            => 1,
    populate          => 1,
    storage_type      => '::DBI::Replicated',
    storage_type_args => {
      balancer_type=>'DBIx::Class::Storage::DBI::Replicated::Balancer::Random'
    },
  );

This method removes the test SQLite database in t/var/BCS.db
and then creates a new, empty database.

This method will call deploy_schema() by default, unless the
deploy flag is set to 0.

This method will call populate_schema() if the populate argument
is set to a true value.

=cut

sub has_custom_dsn {
    return $ENV{"BCS_TEST_DSN"} ? 1 : 0;
}

sub _sqlite_dbfilename {
    return "t/var/BCS.db";
}

sub _sqlite_dbname {
    my $self = shift;
    my %args = @_;
    return $self->_sqlite_dbfilename; # if $args{sqlite_use_file} or $ENV{"BCS_SQLITE_USE_FILE"};
    return ":memory:";
}

sub _database {
    my $self = shift;
    my %args = @_;
    my $db_file = $self->_sqlite_dbname(%args);

    #warn "Removing $db_file";
    #unlink($db_file) if -e $db_file;
    #unlink($db_file . "-journal") if -e $db_file . "-journal";
    mkdir("t/var") unless -d "t/var";

    my $dsn    = $ENV{"BCS_TEST_DSN"} || "dbi:SQLite:${db_file}";
    my $dbuser = $ENV{"BCS_TEST_DBUSER"} || '';
    my $dbpass = $ENV{"BCS_TEST_DBPASS"} || '';

    my @connect_info = ($dsn, $dbuser, $dbpass, { AutoCommit => 1, %args });

    return @connect_info;
}

sub init_schema {
    my $self = shift;
    my %args = @_;
    my $should_deploy = $ENV{"BCS_TEST_DSN"} ? 0 : 1 ;

    my $schema;

    if ($args{compose_connection}) {
      $schema = Bio::Chado::Schema->compose_connection(
                  'Bio::Chado::Schema::Test', $self->_database(%args)
                );
    } else {
      $schema = Bio::Chado::Schema->compose_namespace('Bio::Chado::Schema::Test');
    }

    if ($args{storage_type}) {
      $schema->storage_type($args{storage_type});
    }

    $schema = $schema->connect($self->_database(%args));
    $schema->storage->on_connect_do(['PRAGMA synchronous = OFF']) unless $self->has_custom_dsn;

    unless ( -e _sqlite_dbfilename() ) {
        __PACKAGE__->deploy_schema( $schema, $args{deploy_args} ) if $should_deploy;
        __PACKAGE__->populate_schema( $schema ) if $args{populate};
    }
    return $schema;
}

=head2 deploy_schema

  Bio::Chado::Schema::Test->deploy_schema( $schema );

This method does one of two things to the schema.  It can either call
the experimental $schema->deploy() if the BCSTEST_SQLT_DEPLOY environment
variable is set, otherwise the default is to read in the t/lib/sqlite.sql
file and execute the SQL within. Either way you end up with a fresh set
of tables for testing.

=cut

sub deploy_schema {
    my $self = shift;
    my $schema = shift;
    my $args = shift || {};

    $schema->deploy($args);
    return;
}

=head2 populate_schema

  Bio::Chado::Schema::Test->populate_schema( $schema );

After you deploy your schema you can use this method to populate
the tables with test data.

=cut

sub populate_schema {
    my $self = shift;
    my $schema = shift;

#    $schema->populate('Genre', [
#      [qw/genreid name/],
#      [qw/1        emo/],
#    ]);

}

1;
