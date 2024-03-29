#Copyright 2014 Carnegie Mellon University
#All rights reserved.

#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

#1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

#2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

#3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package CMU::LDAP::389;

use Net::LDAP::Util
  qw(ldap_error_name ldap_error_text ldap_error_desc ldap_explode_dn escape_filter_value escape_dn_value );
use Net::LDAP::Entry;
use base ("CMU::LDAP");
use Net::LDAPS;
use Data::Dumper;
use strict;
use warnings;

require CMU::CFG;
require CMU::Cache;
require CMU::Stats;

my $_389;
my $_cn;

my $log = Log::Log4perl->get_logger();

sub getInstance {
	$log->debug("Calling CMU::LDAP::389::getInstance(self)");
	if ( !defined $_389 ) {
		my $class = shift;
		my $self  = {};
		$_389 = bless $self, $class;

		CMU::CFG::readConfig('configuration.pl');

		$_389->{_server}           = $CMU::CFG::_CFG{'389'}{'server'};
		$_389->{_binddn}           = $CMU::CFG::_CFG{'389'}{'binddn'};
		$_389->{_password}         = $CMU::CFG::_CFG{'389'}{'password'};
		$_389->{_syncou}           = $CMU::CFG::_CFG{'389'}{'syncou'};
		$_389->{_peoplebase}       = $CMU::CFG::_CFG{'389'}{'peoplebase'};
		$_389->{_server}           = $CMU::CFG::_CFG{'389'}{'server'};
		$_389->{_groupobjectclass} = $CMU::CFG::_CFG{'389'}{'groupobjectclass'};
		$_389->{_personobjectclass} =
		  $CMU::CFG::_CFG{'389'}{'personobjectclass'};
		$_389->{_dnattribute}     = $CMU::CFG::_CFG{'389'}{'dnattribute'};
		$_389->{_memberprefix}    = $CMU::CFG::_CFG{'389'}{'memberprefix'};
		$_389->{_env}             = $CMU::CFG::_CFG{'ldap'}{'env'};
		$_389->{_logtoerrorqueue} = $CMU::CFG::_CFG{'ldap'}{'logtoerrorqueue'};
		$_389->{_cache}           = CMU::Cache->new;
		$_389->connect();
	}

	return $_389;
}

sub connect {

	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::389::connect(self)");

	eval {
		$self->{_ldap} =
		  Net::LDAPS->new( $self->{_server}, port => $self->{_port} );
	};

	if ($@) {
		$log->error("Could not create LDAP object because:$!");
		return;
	}

	my $result =
	  $self->{_ldap}->bind( $self->{_binddn}, password => $self->{_password} );

	if ( $result->code ) {
		$log->error( "CMU::LDAP::connect returned with error name: "
			  . ldap_error_name( $result->code )
			  . ", and error description: "
			  . ldap_error_desc( $result->code ) );
		return;
	}

	$log->info("Bind sucessful");
	return;
}

sub disconnect {
	my ($self) = @_;

	$log->debug("Calling CMU::LDAP::389::disconnect(self)");

	if ( defined $self->{_ldap} ) {
		eval { $self->{_ldap}->unbind; };

		if ($@) {
			$log->error("Could not unbind LDAP because:$!");
		}
		undef $self->{_ldap};
	}

	undef $_389;
}

sub createGroup {
	my ( $self, $dn, $description ) = @_;
	$log->debug("Calling CMU::LDAP::389::createGroup(self, $dn)");

	my $entry = Net::LDAP::Entry->new($dn);
	my $cn    = $self->{_amqmesg}->{"name"};

	if ( $description ne '' ) {
		$entry->add(
			'objectClass' => [ 'top', 'groupOfNames' ],
			'cn'          => $cn,
			'description' => $description
		);
	}
	else {
		$entry->add(
			'objectClass' => [ 'top', 'groupOfNames' ],
			'cn'          => $cn
		);
	}

	my $result = $self->ldapUpdate($entry);

	if ( $result->code ) {
		if ( ldap_error_name( $result->code ) eq "LDAP_ALREADY_EXISTS" ) {
			$log->info( "group " . $dn . " already exists" );
		}
		else {
			$log->error(
				    "CMU::LDAP::389::createGroup returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", error description: "
				  . ldap_error_desc( $result->code )
				  . ", changetype: "
				  . $entry->changetype()
				  . ", ldif: "
				  . $entry->ldif() );
			die();
		}
	}
	else {
		$log->info( "Created 389 group " . $dn );
	}

	return $result;
}

sub getGroupDn {
	my ( $self, $groupname ) = @_;
	$log->debug("Calling CMU::LDAP::389::getGroupDn(self, $groupname)");

	$groupname = join( "=", "CN", escape_dn_value($groupname) );

	my $dn = join( ",", $groupname, $self->{_syncou} );

	$log->debug( "groupname " . $groupname . " converted to DN " . $dn );
	return $dn;
}

sub addIsMemberOf {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::389::addIsMemberOf( self, $memberdn, $groupdn)");

	my $result;
	my @attrs = ("dn");
	my $entry =
	  $self->getLdapEntry(
		"!(isMemberOf=" . escape_filter_value($groupdn) . ")",
		\@attrs, $memberdn );

	if ( defined $entry ) {
		$entry->add( 'isMemberOf' => [$groupdn] );

		$result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			if ( ldap_error_name( $result->code ) eq
				"LDAP_TYPE_OR_VALUE_EXISTS" )
			{
				$log->info( " isMemberOf " . $groupdn
					  . " for uid "
					  . $memberdn
					  . " already exists" );
			}
			else {

				$log->error(
					"CMU::LDAP::389::addIsMemberOf returned with error name: "
					  . ldap_error_name( $result->code )
					  . ", error description: "
					  . ldap_error_desc( $result->code )
					  . ", changetype: "
					  . $entry->changetype()
					  . ", ldif: "
					  . $entry->ldif() );
				die();
			}
		}
		else {
			$log->info(
				"Added isMemberOf " . $groupdn . " for uid " . $memberdn );
		}
	}
	else {
		$log->info(
			    "Skipping addIsMemberOf as ldapentry not found with groupdn "
			  . $groupdn
			  . "  not in userdn "
			  . $memberdn );
	}
	return $result;
}

sub removeIsMemberOf {
	my ( $self, $memberdn, $groupdn ) = @_;
	$log->debug(
		"Calling CMU::LDAP::389::removeIsMemberOf( self, $memberdn, $groupdn)"
	);

	my $result;
	my @attrs = ("dn");
	my $entry =
	  $self->getLdapEntry( "(isMemberOf=" . escape_filter_value($groupdn) . ")",
		\@attrs, $memberdn );

	if ( defined $entry ) {
		$entry->delete( 'isMemberOf' => [$groupdn] );

		my $result = $self->ldapUpdate($entry);

		if ( $result->code ) {
			$log->error(
				    "CMU::LDAP::389 removeIsMemberOf returned with error name: "
				  . ldap_error_name( $result->code )
				  . ", error description: "
				  . ldap_error_desc( $result->code )
				  . ", changetype: "
				  . $entry->changetype()
				  . ", ldif: "
				  . $entry->ldif() );
			die();
		}
		else {
			$log->info(
				"Removed isMemberOf " . $groupdn . " for uid " . $memberdn );
		}
	}
	else {
		$log->info(
			    "Skipping removeIsMemberOf as ldapentry not found with groupdn "
			  . $groupdn
			  . "  in userdn "
			  . $memberdn );
	}

	return $result;
}

sub getUidByIsMemberOf {
	my ( $self, $groupdn ) = @_;
	$log->debug("Calling CMU::LDAP::389::getUidByIsMemberOf( self, $groupdn)");

	my $result;
	my @members      = ();
	my @attrs        = ("uid");
	my $memberscount = 0;

	eval {
		$result = $self->ldapSearch(
			"&(isMemberOf="
			  . escape_filter_value($groupdn)
			  . ")(objectClass=cmuAccountPerson)",
			\@attrs, $self->{_peoplebase}
		);

		foreach my $entry ( $result->entries ) {
			push( @members, $entry->get_value("uid") );
		}
		$memberscount = @members;
	};

	if ($@) {
		die();
	}

	$log->debug(
		"Found " . $memberscount . " isMemberOf for group " . $groupdn );
	return @members;
}

sub DESTROY {
	my ($self) = @_;
	$log->debug("Calling CMU::LDAP::389::DESTROY(self)");
}

1;
