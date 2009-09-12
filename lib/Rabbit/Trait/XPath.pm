package Rabbit::Trait::XPath;
use Moose::Role;
use Moose::Util::TypeConstraints;
use Perl6::Junction ();
use Data::Visitor::Callback ();

around '_process_options' => sub {
    my ($orig, $self, $name, $options, @rest) = @_;

    # This should really be:
    # has '+is' => ( is => 'ro', default => 'ro' );
    # but for some unknown reason Moose doesn't allow that
    $options->{'is'} = 'ro' unless exists $options->{'is'};

    # Specifying isa_map builds 'isa' for you
    unless ( exists $options->{'isa'} ) {
        if ( $options->{'isa_map'} ) {
            my @classes;
            foreach my $value ( values %{ $options->{'isa_map'} } ) {
                class_type($value);
                push @classes, $value,
            }
            # Build union isa
            my $isa = join('|',@classes);
            # If traits indicate XPathObjectList, assume an ArrayRef
            if ( Perl6::Junction::any( @{ $options->{'traits'} } ) == qr/^Rabbit::Trait::XPathObjectList$/ ) {
                $isa = "ArrayRef[$isa]";
            }
            # If traits indicate XPathObjectMap, assume a HashRef
            if ( Perl6::Junction::any( @{ $options->{'traits'} } ) == qr/^Rabbit::Trait::XPathObjectMap$/ ) {
                $isa = "HashRef[$isa]";
            }
            $options->{'isa'} = $isa;
        }
    }

    $self->$orig($name, $options, @rest);
};

has 'xpath_query' => (
    is       => 'ro',
    isa      => 'Str|CodeRef',
    required => 1,
);

has '+lazy' => (
    default => 1,
);

has '_isa_map_converted' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

sub _verify_parent_role {
    my ($self, $parent) = @_;

    # Make sure the parent class implements required role
    unless ( $parent->does('Rabbit::Role::Node') ) {
        confess( ref($parent) . " doesn't implement Rabbit::Role::Node");
    }

    return 1;
}

sub _resolve_xpath_query {
    my ($self, $parent) = @_;

    # Figure out if xpath_query is code
    my $query_is_object = blessed($self->xpath_query) ? 1 : 0;
    my $query_is_coderef = ref($self->xpath_query) eq 'CODE' ? 1 : 0;
    my $query_is_code = $query_is_coderef;
       $query_is_code ||= $query_is_object && $self->xpath_query->isa('Class::MOP::Method');

    # Run code reference if necessary to build xpath query.
    # The parent object is the first param to the coderef, not the attribute.
    # This allows the resolution of information in the coderef to happen
    # from the perspective of the class that uses the attribute instead from
    # the perspective of the attribute.
    # Finally overwrite coderef with static value.
    my $xpath_query = $query_is_code ? $self->xpath_query->($parent) : $self->xpath_query;

    return $xpath_query;
}

sub _resolve_class {
    my ($self) = @_;

    # Figure out classes mentioned in type constraint (isa)
    my @classes;
    if ( $self->has_type_constraint ) {
        Data::Visitor::Callback->new({
            object => 'visit_ref',
            'Moose::Meta::TypeConstraint::Union'         => sub { return $_[1]->type_constraints; },
            'Moose::Meta::TypeConstraint::Class'         => sub { push @classes, $_[1]->class; return $_[1]; },
            'Moose::Meta::TypeConstraint::Parameterized' => sub { return $_[1]->type_parameter; },
        })->visit($self->type_constraint);
    }

    # Runtime load each class
    foreach my $class ( @classes ) {
        Class::MOP::load_class($class);
    }

    # Return 0 if multiple classes found,
    # _create_instance() must use $self->isa_map to resolve class name
    return scalar @classes > 1 ? 0 : $classes[0];

}

sub _convert_isa_map {
    my ($self, $parent) = @_;

    # isa_map is optional
    return unless $self->can('isa_map');

    # Don't let it run more than once per trait meta-instance
    return if $self->_isa_map_converted;

    foreach my $key ( keys %{ $self->isa_map } ) {
        # Skip nodes that have no prefix specified
        next unless $key =~ /:/;

        # Find namespace URI in main mapping
        my ($prefix, $node_name) = split(/:/, $key);
        my $ns_uri = $parent->namespace_map->{ $prefix };

        # Stop if namespaceURI was not found, to continue would create unstable behaviour
        confess("Prefix '$prefix' not defined in namespace_map") unless $ns_uri;

        # Replace prefix key with namespaceURI key used by _create_instance()
        my $new_key = '[' . $ns_uri . ']' . $node_name;
        $self->isa_map->{ $new_key } = $self->isa_map->{$key};
        delete $self->isa_map->{$key};
    }

    $self->_isa_map_converted(1);

}

sub _create_instance {
    my ($self, $parent, $class, $node) = @_;

    # Just return undef if no node passed
    # TypeConstraint must be Maybe[XXX] though
    # Used for optional elements
    return unless $node;

    unless( $class ) {
        my $node_name = ( $node->namespaceURI ? '[' . $node->namespaceURI . ']' : "" ) . $node->localname;
        $class = $self->isa_map->{ $node_name };
    }
    confess("Unable to resolve class for node " . $node->nodeName) unless $class;
    my $instance = $class->new(
        xpc           => $parent->xpc,
        node          => $node,
        namespace_map => $parent->namespace_map,
    );
    return $instance;
}

sub _find_node {
    my ($self, $parent, $xpath_query) = @_;
    $self->_verify_parent_role( $parent );
    my $node = $parent->xpc->find( $xpath_query, $parent->node );
    return unless blessed($node); # No node found, just return undef (optional elements)
    $node = $node->shift if $node->isa('XML::LibXML::NodeList'); # Get first item if multiple results
    return $node;
}

sub _find_nodes {
    my ($self, $parent, $xpath_query) = @_;
    $self->_verify_parent_role( $parent );
    my @nodes;
    foreach my $node ( $parent->xpc->findnodes( $xpath_query, $parent->node ) ) {
        push @nodes, $node if blessed($node);
    }
    return wantarray ? @nodes : \@nodes;
}

no Moose::Role;
no Moose::Util::TypeConstraints;

1;

=head1 NAME

Rabbit::Trait::XPath - Moose-based XML loader - base role for other xpath traits


=head1 SYNOPSIS

    package Rabbit::Trait::XPathSomething;
    use Moose::Role;
    with 'Rabbit::Trait::XPath';

    1;

=head1 DESCRIPTION

This module provides base methods for other xpath traits.

See L<Rabbit> for a more complete example.


=head1 ATTRIBUTES


=over 12


=item C<xpath_query>

A string or a coderef that generates a string that is the XPath query to use to find the wanted value. Read Only.


=item C<lazy>

Indicates that the parent attribute will be lazy-loaded on first use. Read Only.


=item C<meta>

Moose meta object.


=back


=head1 BUGS

See L<Rabbit/BUGS>.


=head1 SUPPORT

See L<Rabbit/SUPPORT>.


=head1 AUTHOR

See L<Rabbit/AUTHOR>.


=head1 COPYRIGHT

See L<Rabbit/COPYRIGHT>.

=head1 LICENSE

See L<Rabbit/LICENSE>.


=cut
