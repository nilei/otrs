# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

use File::Path qw(mkpath rmtree);

# get selenium object
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        # get helper object
        $Kernel::OM->ObjectParamAdd(
            'Kernel::System::UnitTest::Helper' => {
                RestoreSystemConfiguration => 1,
            },
        );
        my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

        # create test user and login
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => ['admin'],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get sysconfig object
        my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

        # disable PGP in config
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'PGP',
            Value => 0,
        );

        # get config object
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

        # create test PGP path and set it in sysConfig
        my $PGPPath = $ConfigObject->Get('Home') . "/var/tmp/pgp";
        mkpath( [$PGPPath], 0, 0770 );    ## no critic

        # get script alias
        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        # navigate to AdminPGP screen
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AdminPGP");

        # check widget sidebar when PGP sysconfig is disabled
        $Self->True(
            $Selenium->find_element( 'h3 span.Warning', 'css' ),
            "Widget sidebar with warning message is displayed.",
        );
        $Self->True(
            $Selenium->find_element("//button[\@value='Enable it here!']"),
            "Button 'Enable it here!' to the PGP SysConfig is displayed.",
        );

        # enable PGP in config
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'PGP',
            Value => 1,
        );

        # set wrong PGP bin in config
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'PGP::Bin',
            Value => 'SomePGP/Bin',
        );

        # let mod_perl / Apache2::Reload pick up the changed configuration
        sleep 3;

        # refresh AdminPGP screen
        $Selenium->VerifiedRefresh();

        # check widget sidebar when PGP sysconfig does not work
        $Self->True(
            $Selenium->find_element( 'h3 span.Error', 'css' ),
            "Widget sidebar with error message is displayed.",
        );
        $Self->True(
            $Selenium->find_element("//button[\@value='Configure it here!']"),
            "Button 'Configure it here!' to the PGP SysConfig is displayed.",
        );

        # set PGP path in config
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'PGP::Options',
            Value => "--homedir $PGPPath --batch --no-tty --yes",
        );

        # reset PGP bin in config
        $SysConfigObject->ConfigItemReset(
            Name => 'PGP::Bin',
        );

        # let mod_perl / Apache2::Reload pick up the changed configuration
        sleep 3;

        # refresh AdminSPGP screen
        $Selenium->VerifiedRefresh();

        # add first test PGP key
        $Selenium->find_element("//a[contains(\@href, \'Action=AdminPGP;Subaction=Add' )]")->VerifiedClick();

        my $Location1 = $ConfigObject->Get('Home')
            . "/scripts/test/sample/Crypt/PGPPrivateKey-1.asc";

        $Selenium->find_element( "#FileUpload", 'css' )->send_keys($Location1);
        $Selenium->find_element("//button[\@type='submit']")->VerifiedClick();

        # add second test PGP key
        $Selenium->find_element("//a[contains(\@href, \'Action=AdminPGP;Subaction=Add' )]")->VerifiedClick();
        my $Location2 = $ConfigObject->Get('Home')
            . "/scripts/test/sample/Crypt/PGPPrivateKey-2.asc";

        $Selenium->find_element( "#FileUpload", 'css' )->send_keys($Location2);
        $Selenium->find_element("//button[\@type='submit']")->VerifiedClick();

        # check if test PGP keys show on AdminPGP screen
        my %PGPKey = (
            1 => "unittest\@example.com",
            2 => "unittest2\@example.com",
        );

        $Self->True(
            index( $Selenium->get_page_source(), $PGPKey{1} ) > -1,
            "$PGPKey{1} test PGP key found on page",
        );
        $Self->True(
            index( $Selenium->get_page_source(), $PGPKey{2} ) > -1,
            "$PGPKey{2} test PGP key found on page",
        );

        # test search filter
        $Selenium->find_element( "#Search", 'css' )->send_keys( $PGPKey{1} );
        $Selenium->find_element( "#Search", 'css' )->VerifiedSubmit();

        $Self->True(
            index( $Selenium->get_page_source(), $PGPKey{1} ) > -1,
            "$PGPKey{1} test PGP key found on page",
        );
        $Self->False(
            index( $Selenium->get_page_source(), $PGPKey{2} ) > -1,
            "$PGPKey{2} test PGP key is not found on page",
        );

        #clear search filter
        $Selenium->find_element( "#Search", 'css' )->clear();
        $Selenium->find_element( "#Search", 'css' )->VerifiedSubmit();

        # set test PGP in config so we can delete them
        $ConfigObject->Set(
            Key   => 'PGP',
            Value => 1,
        );
        $ConfigObject->Set(
            Key   => 'PGP::Options',
            Value => "--homedir $PGPPath --batch --no-tty --yes",
        );

        # delete test PGP keys
        for my $Count ( 1 .. 2 ) {
            my @Keys = $Kernel::OM->Get('Kernel::System::Crypt::PGP')->KeySearch(
                Search => $PGPKey{$Count},
            );

            for my $Key (@Keys) {
                if ( $Key->{Type} eq 'sec' ) {

                    # click on delete secure key
                    $Selenium->find_element(
                        "//a[contains(\@href, \'Subaction=Delete;Type=sec;Key=$Key->{FingerprintShort}' )]"
                    )->VerifiedClick();
                    $Self->True(
                        $Key,
                        "PGPKey - $Key->{Identifier} deleted",
                    );

                    # click on delete public key
                    $Selenium->find_element(
                        "//a[contains(\@href, \'Subaction=Delete;Type=pub;Key=$Key->{FingerprintShort}' )]"
                    )->VerifiedClick();
                    $Self->True(
                        $Key,
                        "PGPKey - $Key->{Identifier} deleted",
                    );
                }
            }
        }

        # remove test PGP path
        my $Success = rmtree( [$PGPPath] );
        $Self->True(
            $Success,
            "Directory deleted - '$PGPPath'",
        );

    }

);

1;
