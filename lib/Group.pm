# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the AssigneeList Bugzilla Extension.
#
# The Initial Developer of the Original Code is Ali Ustek
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Ali Ustek <AliUstek@gmail.com>
use strict;

package Bugzilla::Extension::AssigneeList::Group;

use base qw(Bugzilla::Object);

use Bugzilla::Error;
use Bugzilla::Util;
use Scalar::Util qw(blessed);

use Bugzilla::Extension::AssigneeList::Constants;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'componentleadsgroup';
use constant LIST_ORDER => 'sortkey, name';

use constant DB_COLUMNS => qw(
    id
    component_id
    name
    sortkey
);

use constant UPDATE_COLUMNS => qw(
    name
    sortkey
);

use constant VALIDATORS => {
    name         => \&_check_name,
    sortkey	=> \&_check_sortkey,
};

################################
# Validators
################################

sub _check_name {
    my ($invocant, $name, undef, $params) = @_;
    my $component_id = blessed($invocant) ? 
    									$invocant->component_id : $params->{component_id};

	$name = trim($name);
    $name || ThrowUserError('label_required');
    if (length($name) > MAX_LABEL_LENGTH) {
        ThrowUserError('label_too_long', { label => $name });
    }
    
    my $group = new Bugzilla::Extension::AssigneeList::Group({
                                         name => $name, 
                                         component_id  => $component_id,
                                    });
    if ($group && (!ref $invocant || $group->id != $invocant->id)) {
    	warn "GID: ".$group->id. " GCID: ".$group->component_id. " CID: ".$component_id;
        ThrowUserError('assigneegroup_already_exists', { name    => $group->name });
    }

    return $name;
}

sub _check_sortkey {
    my ($invocant, $sortkey) = @_;
    
    $sortkey ||= 0;
    
    detaint_natural($sortkey) 
    || ThrowUserError('invalid_sortkey', { sortkey => $sortkey });
    return $sortkey;
}

################################
# Methods
################################

sub set_name { $_[0]->set('name', $_[1]); }
sub set_sortkey { $_[0]->set('sortkey', $_[1]); }

################################
# Accessors
################################

sub component_id { return $_[0]->{'component_id'}; }
sub name                { return $_[0]->{'name'}; }
sub sortkey            { return $_[0]->{'sortkey'}; }

###############################

1;
