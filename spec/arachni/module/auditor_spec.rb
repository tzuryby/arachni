require_relative '../../spec_helper'
require_from_root( 'framework' )

class AuditorTest
    include Arachni::Module::Auditor
    include Arachni::UI::Output

    def initialize( framework )
        @framework = framework
        http.trainer.set_page( page )
        mute!
    end

    def page
        @page ||= Arachni::Parser::Page.new(
            url:  @framework.opts.url.to_s,
            body: 'Match this!',
            method: 'get'
        )
    end

    def http
        @framework.http
    end

    def framework
        @framework
    end

    def load_page_from( url )
        http.get( url ).on_complete {
            |res|
            @page = Arachni::Parser::Page.from_http_response( res, framework.opts )
        }
        http.run
    end

    def self.info
        {
            :name => 'Test auditor',
            :issue => {
                :name => 'Test issue'
            }
        }
    end
end

describe Arachni::Module::Auditor do

    before :all do
        @opts = Arachni::Options.instance
        @opts.audit_links = true

        @opts.url = @url = server_url_for( :auditor )

        @framework = Arachni::Framework.new( @opts )
        @auditor = AuditorTest.new( @framework )
    end

    after :each do
        @framework.modules.results.clear
    end

    it 'should #register_results' do
        issue = Arachni::Issue.new( name: 'Test issue', url: @url )
        @auditor.register_results( [ issue ] )

        logged_issue = @framework.modules.results.first
        logged_issue.should be_true

        logged_issue.name.should == issue.name
        logged_issue.url.should  == issue.url
    end

    describe :log_remote_file_if_exists do
        before do
            @base_url = @url + '/log_remote_file_if_exists/'
        end

        it 'should log issue if file exists' do
            file = @base_url + 'true'
            @auditor.log_remote_file_if_exists( file )
            @framework.http.run

            logged_issue = @framework.modules.results.first
            logged_issue.should be_true

            logged_issue.url.split( '?' ).first.should == file
            logged_issue.elem.should == Arachni::Issue::Element::PATH
            logged_issue.id.should == 'true'
            logged_issue.injected.should == 'true'
            logged_issue.mod_name.should == @auditor.class.info[:name]
            logged_issue.name.should == @auditor.class.info[:issue][:name]
            logged_issue.verification.should be_false
        end

        it 'should not log issue if file doesn\'t exist' do
            @auditor.log_remote_file_if_exists( @base_url + 'false' )
            @framework.http.run
            @framework.modules.results.should be_empty
        end
    end

    describe :remote_file_exist? do
        before do
            @base_url = @url + '/log_remote_file_if_exists/'
        end

        after { @framework.http.run }

        it 'should return true if file exists' do
            @framework.http.get( @base_url + 'true' ).on_complete {
                |res|
                @auditor.remote_file_exist?( res ).should be_true
            }
        end

        it 'should return false if file doesn\'t exists' do
            @framework.http.get( @base_url + 'false' ).on_complete {
                |res|
                @auditor.remote_file_exist?( res ).should be_false
            }
        end
    end


    describe :log_remote_file do
        it 'should log a remote file' do
            file = @url + '/log_remote_file_if_exists/true'
            @framework.http.get( file ).on_complete {
                |res|
                @auditor.log_remote_file( res )
            }
            @framework.http.run

            logged_issue = @framework.modules.results.first
            logged_issue.should be_true

            logged_issue.url.split( '?' ).first.should == file
            logged_issue.elem.should == Arachni::Issue::Element::PATH
            logged_issue.id.should == 'true'
            logged_issue.injected.should == 'true'
            logged_issue.mod_name.should == @auditor.class.info[:name]
            logged_issue.name.should == @auditor.class.info[:issue][:name]
            logged_issue.verification.should be_false
        end
    end

    describe :log_issue do
        it 'should log an issue' do
            opts = { name: 'Test issue', url: @url }
            @auditor.log_issue( opts )

            logged_issue = @framework.modules.results.first
            logged_issue.name.should == opts[:name]
            logged_issue.url.should  == opts[:url]
        end
    end

    describe :match_and_log do

        before do
            @base_url = @url + '/match_and_log'
            @regex = {
                :valid   => /match/i,
                :invalid => /will not match/,
            }
        end

        context 'when given a response' do
            after do
                @framework.http.run
            end

            it 'should log issue if pattern matches' do
                @framework.http.get( @base_url ).on_complete {
                    |res|

                    regexp = @regex[:valid]

                    @auditor.match_and_log( regexp, res.body )

                    logged_issue = @framework.modules.results.first
                    logged_issue.should be_true

                    logged_issue.url.should == @opts.url.to_s
                    logged_issue.elem.should == Arachni::Issue::Element::BODY
                    logged_issue.opts[:regexp].should == regexp.to_s
                    logged_issue.opts[:match].should == 'Match'
                    logged_issue.opts[:element].should == Arachni::Issue::Element::BODY
                    logged_issue.regexp.should == regexp.to_s
                    logged_issue.verification.should be_false
                }
            end

            it 'should not log issue if pattern doesn\'t match' do
                @framework.http.get( @base_url ).on_complete {
                    |res|
                    @auditor.match_and_log( @regex[:invalid], res.body )
                    @framework.modules.results.should be_empty
                }
            end
        end

        context 'when defaulting to current page' do
            it 'should log issue if pattern matches' do
                regexp = @regex[:valid]

                @auditor.match_and_log( regexp )

                logged_issue = @framework.modules.results.first
                logged_issue.should be_true

                logged_issue.url.should == @opts.url.to_s
                logged_issue.elem.should == Arachni::Issue::Element::BODY
                logged_issue.opts[:regexp].should == regexp.to_s
                logged_issue.opts[:match].should == 'Match'
                logged_issue.opts[:element].should == Arachni::Issue::Element::BODY
                logged_issue.regexp.should == regexp.to_s
                logged_issue.verification.should be_false
            end

            it 'should not log issue if pattern doesn\'t match ' do
                @auditor.match_and_log( @regex[:invalid] )
                @framework.modules.results.should be_empty
            end
        end
    end

    describe :log do

        before do
            @log_opts = {
                altered:  'foo',
                injected: 'foo injected',
                id: 'foo id',
                regexp: /foo regexp/,
                match: 'foo regexp match',
                element: Arachni::Issue::Element::LINK
            }
        end


        context 'when given a response' do

            after { @framework.http.run }

            it 'populates and logs an issue with response data' do
                @framework.http.get( @opts.url.to_s ).on_complete {
                    |res|

                    @auditor.log( @log_opts, res )

                    logged_issue = @framework.modules.results.first
                    logged_issue.should be_true

                    logged_issue.url.should == res.effective_url
                    logged_issue.elem.should == Arachni::Issue::Element::LINK
                    logged_issue.opts[:regexp].should == @log_opts[:regexp].to_s
                    logged_issue.opts[:match].should == @log_opts[:match]
                    logged_issue.opts[:element].should == Arachni::Issue::Element::LINK
                    logged_issue.regexp.should == @log_opts[:regexp].to_s
                    logged_issue.verification.should be_false
                }
            end
        end

        context 'when it defaults to current page' do
            it 'populates and logs an issue with page data' do
                @auditor.log( @log_opts )

                logged_issue = @framework.modules.results.first
                logged_issue.should be_true

                logged_issue.url.should == @auditor.page.url
                logged_issue.elem.should == Arachni::Issue::Element::LINK
                logged_issue.opts[:regexp].should == @log_opts[:regexp].to_s
                logged_issue.opts[:match].should == @log_opts[:match]
                logged_issue.opts[:element].should == Arachni::Issue::Element::LINK
                logged_issue.regexp.should == @log_opts[:regexp].to_s
                logged_issue.verification.should be_false
            end
        end

    end

    describe :audit do

        context 'when called with no opts' do
            it 'should use the defaults' do
                @auditor.load_page_from( @url + '/audit/link' )
                @auditor.audit( 'this is what we inject' )
                @framework.http.run
                @framework.modules.results.size.should == 4
            end
        end

        context 'when called with option' do
            describe :format do
                describe 'Arachni::Module::Auditor::Format::STRAIGHT' do
                    it 'should inject the seed as is'
                end
                describe 'Arachni::Module::Auditor::Format::APPEND' do
                    it 'should append the seed to the existing value of the input'
                end
                describe 'Arachni::Module::Auditor::Format::NULL' do
                    it 'should terminate the seed with a null character'
                end
                describe 'Arachni::Module::Auditor::Format::SEMICOLON' do
                    it 'should terminate the seed with a semicolon'
                end
            end

            describe :elements do
                describe 'Arachni::Module::Auditor::Element::LINK' do
                    it 'should audit links'
                end
                describe 'Arachni::Module::Auditor::Element::FORM' do
                    it 'should audit forms'
                end
                describe 'Arachni::Module::Auditor::Element::COOKIE' do
                    it 'should audit cookies'
                end
                describe 'Arachni::Module::Auditor::Element::HEADER' do
                    it 'should audit headers'
                end
            end

            describe :regexp do
                context 'with :match' do
                    it 'should verify the matched data with the provided string'
                end

                context 'without :match' do
                    it 'should try to match the provided pattern'
                end
            end

            describe :substring do
                it 'should try to match the provided substring'
            end

            describe :train do
                context true do
                    it 'should parse the responses and feed any new elements back to the framework to be audited'
                end

                context false do
                    it 'should skip analysis'
                end
            end

            describe :redundant do
                context true do
                    it 'should allow redundant requests/audits'
                end

                context false do
                    it 'should not allow redundant requests/audits'
                end
            end

            describe :async do
                context true do
                    it 'should perform all HTTP requests asynchronously'
                end

                context false do
                    it 'should perform all HTTP requests asynchronously'
                end
            end

        end

        context 'when called with a block' do
            it 'should delegate analysis and logging to caller'
        end

    end

end