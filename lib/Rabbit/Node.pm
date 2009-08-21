package Rabbit::Node;
use Moose;

use Encode ();

has 'node' => (
    is       => 'ro',
    isa      => 'XML::LibXML::Node',
    required => 1,
);

has 'xpc' => (
    is       => 'ro',
    isa      => 'XML::LibXML::XPathContext',
    required => 1,
);

sub dump {
    my ($self) = @_;
    return Encode::decode(
        $self->node->ownerDocument->actualEncoding,
        $self->node->toString(1),
    );
}

no Moose;
__PACKAGE__->meta->make_immutable();

1;

=head1 NAME

Rabbit::Node - Moose-based XML loader - node base class


=head1 SYNOPSIS

    package MyXMLSyntaxNode;
    use Moose;
    extends 'Rabbit::Node';

    has title => (
        is          => 'ro',
        isa         => 'Str',
        traits      => [qw(XPathValue)],
        xpath_query => './@title',
    );

    no Moose;
    __PACKAGE__->meta->make_immutable();

    1;

=head1 DESCRIPTION

This module provides the base node attribute used to hold a specific node in the XML docuent tree.

See L<Rabbit> for a more complete example.


=head1 ATTRIBUTES


=over 12


=item C<new>

Standard Moose constructor.


=item C<node>

An instance of a L<XML::LibXML::Node> class representing a node in an XML document tree. Read Only.


=item C<xpc>

An instance of a L<XML::LibXML::XPathContext> class initialized with the C<node> attribute. Read Only.


=item C<dump>

Dumps the XML of the current node as a native perl string.


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
