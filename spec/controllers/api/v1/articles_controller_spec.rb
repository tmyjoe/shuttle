# encoding: utf-8

# Copyright 2014 Square Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

require 'spec_helper'

describe Api::V1::ArticlesController do
  def expect_invalid_api_token_response
    expect(response.status).to eql(401)
    expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>[{"message"=>"Invalid project API TOKEN"}]}})
  end

  shared_examples_for "invalid api token" do
    it "errors if no api_token is provided" do
      send request_type, action, params.merge(format: :json)
      expect(response.status).to eql(401)
      expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>[{"message"=>"Invalid project API TOKEN"}]}})
    end

    it "errors if wrong api_token is provided" do
      send request_type, action, params.merge(format: :json, api_token: "fake")
      expect(response.status).to eql(401)
      expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>[{"message"=>"Invalid project API TOKEN"}]}})
    end
  end

  describe "#index" do
    it_behaves_like "invalid api token" do
      let(:request_type) { :get }
      let(:action) { :index }
      let(:params) { {} }
    end

    it "retrieves all Articles in the project, but not the Articles in other projects" do
      Article.any_instance.stub(:import!) # prevent auto imports
      project = FactoryGirl.create(:project, repository_url: nil)
      article1 = FactoryGirl.create(:article, project: project)
      article2 = FactoryGirl.create(:article, project: project)
      article2.update! ready: true

      2.times { FactoryGirl.create(:article) }

      get :index, api_token: project.api_token, format: :json

      expect(response.status).to eql(200)
      expect(JSON.parse(response.body)).to eql([{"name"=>article1.name, "ready"=>false}, {"name"=>article2.name, "ready"=>true}])
    end
  end

  describe "#create" do
    let(:project) { FactoryGirl.create(:project, repository_url: nil, base_rfc5646_locale: 'en', targeted_rfc5646_locales: { 'fr' => true, 'es' => false } ) }

    it_behaves_like "invalid api token" do
      let(:request_type) { :post }
      let(:action) { :create }
      let(:params) { {} }
    end

    it "doesn't create a Article without a name or source_copy, shows the errors to user" do
      post :create, api_token: project.api_token, format: :json
      expect(response.status).to eql(400)
      expect(Article.count).to eql(0)
      expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>{"name_sha"=>["is not a valid SHA2 digest"], "name"=>["can’t be blank"], "sections_hash"=>["can’t be blank"]}}})
    end

    it "creates an Article, its Sections, inherits locale settings from Project" do
      post :create, api_token: project.api_token, name: "testname", sections_hash: {"title" => "<p>a</p><p>b</p>", "body" => "<p>a</p><p>c</p>"}, format: :json
      expect(response.status).to eql(202)
      expect(Article.count).to eql(1)
      article = Article.last
      expect(article.name).to eql("testname")
      expect(article.sections.map { |section| [section.name, section.source_copy, section.active] }.sort).to eql([["title", "<p>a</p><p>b</p>", true], ["body", "<p>a</p><p>c</p>", true]].sort)
      expect(article.keys.count).to eql(4)
      expect(article.translations.count).to eql(12)
      expect(article.base_rfc5646_locale).to eql('en')
      expect(article.targeted_rfc5646_locales).to eql({ 'fr' => true, 'es' => false })
      expect(article.base_locale).to eql(Locale.from_rfc5646('en'))
      expect(article.targeted_locales.map(&:rfc5646).sort).to eql(%w(es fr).sort)
    end

    it "creates an Article, has its own locale settings different from those of Project's" do
      post :create, api_token: project.api_token, name: "testname", sections_hash: {"title" => "<p>a</p><p>b</p>"}, base_rfc5646_locale: 'en-US', targeted_rfc5646_locales: { 'ja' => true }, format: :json
      expect(response.status).to eql(202)
      expect(Article.count).to eql(1)
      article = Article.last
      expect(article.keys.count).to eql(2)
      expect(article.translations.count).to eql(4)
      expect(article.base_rfc5646_locale).to eql('en-US')
      expect(article.targeted_rfc5646_locales).to eql({ 'ja' => true })
      expect(article.base_locale).to eql(Locale.from_rfc5646('en-US'))
      expect(article.targeted_locales.map(&:rfc5646)).to eql(%w(ja))
    end

    it "doesn't create a Article in a Project with a duplicate key name" do
      FactoryGirl.create(:article, project: project, name: "testname", sections_hash: {"title" => "<p>a</p><p>b</p>"})
      post :create, api_token: project.api_token, name: "testname", sections_hash: {"title" => "<p>a</p><p>b</p>"}, format: :json
      expect(response.status).to eql(400)
      expect(Article.count).to eql(1)
      expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>{"name"=>["already taken"]}}})
    end
  end

  describe "#show" do
    let(:project) { FactoryGirl.create(:project, repository_url: nil, targeted_rfc5646_locales: { 'fr' => true, 'es' => false } ) }
    let(:article) { FactoryGirl.create(:article, project: project, name: "test", sections_hash: {"main" => "<p>a</p><p>b</p>"}) }

    it_behaves_like "invalid api token" do
      let(:request_type) { :get }
      let(:action) { :show }
      let(:params) { { name: article.name } }
    end

    it "shows details of an Article" do
      get :show, api_token: project.api_token, name: article.name, format: :json

      expect(response.status).to eql(200)
      response_json = JSON.parse(response.body)
      expect(response_json["sections_hash"]).to eql({"main"=>"<p>a</p><p>b</p>"})
    end
  end

  describe "#update" do
    before :each do
      @project = FactoryGirl.create(:project, repository_url: nil, targeted_rfc5646_locales: { 'fr' => true, 'es' => false } )
      @article = FactoryGirl.create(:article, project: @project, name: "test", sections_hash: { "main" => "<p>a</p><p>b</p>", "second" => "<p>y</p><p>z</p>", "third" => "<p>t</p>" })
      @article.reload
    end

    it_behaves_like "invalid api token" do
      let(:request_type) { :patch }
      let(:action) { :update }
      let(:params) { { name: @article.name } }
    end

    it "updates an Article's sections_hash and targeted_rfc5646_locales" do
      patch :update, api_token: @project.api_token, name: @article.name, sections_hash: { "main" => "<p>a</p><p>x</p><p>b</p>", "sub" => "<p>y</p><p>z</p>", "third" => "<p>t</p>" }, targeted_rfc5646_locales: { 'fr' => true, 'es' => false, 'tr' => false }, format: :json
      expect(response.status).to eql(202)
      article = Article.first
      expect(article.sections.count).to eql(4)
      expect(article.active_sections.count).to eql(3)

      main_section = article.active_sections.for_name("main").first
      sub_section = article.active_sections.for_name("sub").first
      third_section = article.active_sections.for_name("third").first
      second_section = article.inactive_sections.for_name("second").first

      expect(main_section.keys.count).to eql(3)
      expect(main_section.translations.count).to eql(12) # a new locale is added with the update
      expect(sub_section.keys.count).to eql(2)
      expect(sub_section.translations.count).to eql(8)
      expect(third_section.keys.count).to eql(1)
      expect(third_section.translations.count).to eql(4)
      expect(second_section.keys.count).to eql(2)
      expect(second_section.translations.count).to eql(6) # since this is inactivated, this shouldn't have picked the new locale's translations
    end

    it "can update targeted_rfc5646_locales" do
      patch :update, api_token: @project.api_token, name: @article.name, targeted_rfc5646_locales: { 'fr' => true }, format: :json
      expect(response.status).to eql(202)
      expect(Article.count).to eql(1)
      expect(@article.reload.targeted_rfc5646_locales).to eql({ 'fr' => true })
    end

    it "can update source_copy without updating targeted_rfc5646_locales" do
      @article.update! targeted_rfc5646_locales: { 'fr' => true }
      patch :update, api_token: @project.api_token, name: @article.name, sections_hash: { "main" => "<p>a</p><p>x</p><p>b</p>" }, format: :json
      expect(response.status).to eql(202)
      expect(Article.count).to eql(1)
      expect(@article.reload.targeted_rfc5646_locales).to eql({ 'fr' => true })
      expect(@article.active_sections.pluck(:source_copy)).to eql(["<p>a</p><p>x</p><p>b</p>"])
    end

    it "errors if source copy is attempted to be updated before the first import didn't finish yet" do
      @article.update! last_import_requested_at: 1.minute.ago, last_import_finished_at: nil
      patch :update, api_token: @project.api_token, name: @article.name, sections_hash: { "main" => "<p>a</p><p>x</p><p>b</p>" }, format: :json
      expect(response.status).to eql(400)
      expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>{"base"=>["latest requested import is not yet finished"]}}})
    end

    it "errors if source copy is attempted to be updated before a subsequent import didn't finish yet" do
      @article.update! last_import_requested_at: 1.hour.ago, last_import_finished_at: 2.hours.ago
      patch :update, api_token: @project.api_token, name: @article.name, sections_hash: { "main" => "<p>a</p><p>x</p><p>b</p>" }, format: :json
      expect(response.status).to eql(400)
      expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>{"base"=>["latest requested import is not yet finished"]}}})
    end

    it "allows updating non-import related fields such as emails and description even if the previous import didn't finish yet" do
      @article.update! last_import_requested_at: 1.hour.ago, last_import_finished_at: 2.hours.ago, email: "test@example.com", description: "test"
      expect(@article.email).to eql("test@example.com")
      expect(@article.description).to eql("test")
      patch :update, api_token: @project.api_token, name: @article.name, email: "test2@example.com", description: "test 2", format: :json
      expect(response.status).to eql(202)
      expect(@article.reload.email).to eql("test2@example.com")
      expect(@article.description).to eql("test 2")
    end

    it "errors if update fails" do
      patch :update, api_token: @project.api_token, name: @article.name, sections_hash: {}, email: "fake", targeted_rfc5646_locales: {'asdaf-sdfsfs-adas'=> nil}, format: :json
      expect(response.status).to eql(400)
      expect(JSON.parse(response.body)).to eql({ "error" => { "errors"=> { "sections_hash" => ["can’t be blank"], "email" => ["invalid"], "targeted_rfc5646_locales" => ["invalid"] } } })
    end
  end

  describe "#manifest" do
    let(:project) { FactoryGirl.create(:project, repository_url: nil, targeted_rfc5646_locales: { 'fr' => true, 'ja' => true, 'es' => false } ) }
    let(:article) { FactoryGirl.create(:article, project: project, name: "test", sections_hash: { "title" => "<p>hello</p>", "body" => "<p>a</p><p>b</p>" } ) }

    it_behaves_like "invalid api token" do
      let(:request_type) { :get }
      let(:action) { :manifest }
      let(:params) { { name: article.name } }
    end

    it "errors if not all required locales are ready (i.e. translated)" do
      get :manifest, api_token: project.api_token, name: article.name, format: :json
      expect(response.status).to eql(400)
      expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>[{"message"=>"#<Exporter::Article::NotReadyError: Exporter::Article::NotReadyError>"}]}})
    end

    it "downloads the manifest of a Article" do
      article.translations.in_locale(*article.required_locales).each do |translation|
        translation.update! copy: "<p>translated</p>", approved: true
      end
      article.keys.reload.each(&:recalculate_ready!)
      get :manifest, api_token: project.api_token, name: article.name, format: :json
      expect(response.status).to eql(200)
      expect(JSON.parse(response.body)).to eql({ "fr" => { "title" => "<p>translated</p>", "body" => "<p>translated</p><p>translated</p>" }, "ja" => { "title" => "<p>translated</p>", "body" => "<p>translated</p><p>translated</p>" } })
    end
  end

  describe "#params_for_create" do
    let(:project) { FactoryGirl.create(:project, repository_url: nil) }

    it "permits key, sections_hash, description, email, base_rfc5646_locale targeted_rfc5646_locales; but not id or project_id fields" do
      post :create, api_token: project.api_token, name: "t", sections_hash: { "t" => "t" }, description: "t", email: "t@example.com", base_rfc5646_locale: 'en', targeted_rfc5646_locales: { 'fr' => true }, id: 300, project_id: 4, format: :json
      expect(controller.send :params_for_create).to eql({"name"=>"t", "sections_hash"=>{"t" => "t"}, "description"=>"t", "email"=>"t@example.com", "base_rfc5646_locale"=>"en", "targeted_rfc5646_locales"=>{"fr"=>true}})
    end

    it "doesn't include sections_hash or targeted_rfc5646_locales in the permitted params (this is tested separately because it's a special case due to being a hash field)" do
      post :create, api_token: project.api_token, name: "t", format: :json
      expect(controller.send :params_for_create).to eql({"name"=>"t"})
    end
  end

  describe "#params_for_update" do
    let(:project) { FactoryGirl.create(:project, repository_url: nil) }
    let(:article) { FactoryGirl.create(:article, project: project, name: "t") }

    it "permits sections_hash, description, email, targeted_rfc5646_locales; but not id, project_id, key or base_rfc5646_locale fields" do
      patch :update, api_token: project.api_token, name: article.name, sections_hash: { "t" => "t" }, description: "t", email: "t@example.com", base_rfc5646_locale: 'en', targeted_rfc5646_locales: { 'fr' => true }, id: 300, project_id: 4, format: :json
      expect(controller.send :params_for_update).to eql({"sections_hash" => { "t" => "t" }, "description"=>"t", "email"=>"t@example.com", "targeted_rfc5646_locales"=>{"fr"=>true}})
    end

    it "doesn't include sections_hash and targeted_rfc5646_locales in the permitted params (this is tested separately because it's a special case due to being a hash field)" do
      patch :update, api_token: project.api_token, name: article.name, sections_hash: { "t" => "t" }, format: :json
      expect(controller.send :params_for_update).to eql({"sections_hash" => { "t" => "t" }})
    end
  end

  context "[INTEGRATION TESTS]" do
    # This is a real life example. sample_article__original.html was copied and pasted from the help center's website. it was shortened to make tests faster
    it "handles creation, update, update, status, manifest, status, manifest requests in that order" do
      Article.delete_all
      project = FactoryGirl.create(:project, repository_url: nil, targeted_rfc5646_locales: { 'fr' => true } )

      # Create
      post :create, api_token: project.api_token, name: "support-article", sections_hash: { "title" => "<p>AAA</p><p>BBB</p>", "banner" => "<p>XXX</p><p>YYY</p>", "main" => File.read(Rails.root.join('spec', 'fixtures', 'article_files', 'sample_article__original.html')) }, format: :json
      expect(response.status).to eql(202)
      expect(Article.count).to eql(1)
      article = Article.first
      original_article_ids = article.keys.map(&:id)
      expect(article.active_sections.count).to eql(3)
      expect(article.inactive_sections.count).to eql(0)
      expect(article.keys.count).to eql(65)
      expect(article.active_keys.count).to eql(65)
      expect(article.translations.count).to eql(130)

      # Update: change targeted_rfc5646_locales. previously this defaulted to project settings, this time, put it into the Article
      patch :update, api_token: project.api_token, name: "support-article", targeted_rfc5646_locales: { 'fr' => true, 'es' => false }, format: :json
      expect(response.status).to eql(202)
      updated_article_ids = article.reload.keys.map(&:id)
      expect(article.active_sections.count).to eql(3)
      expect(article.inactive_sections.count).to eql(0)
      expect(article.keys.count).to eql(65)
      expect((updated_article_ids - original_article_ids).length).to eql(0) # to make sure that we reused the old keys
      expect(article.active_keys.count).to eql(65)
      expect(article.translations.count).to eql(195)

      # Update
      # this source copy has 1 changed word, 2 added divs one of which is a duplicate of an existing div, and 1 removed div
      patch :update, api_token: project.api_token, name: "support-article", sections_hash: { "title" => "<p>AAA</p><p>GGG</p><p>BBB</p>", "header" => "<p>111</p>", "footer" => "<p>111</p>", "main" => File.read(Rails.root.join('spec', 'fixtures', 'article_files', 'sample_article__updated.html')) }, format: :json
      expect(response.status).to eql(202)
      updated_article_ids = article.reload.keys.map(&:id)
      expect(article.active_sections.count).to eql(4)
      expect(article.inactive_sections.count).to eql(1)
      expect(article.keys.count).to eql(71) # +3 comes from file changes => 2 (addition) + 1 (change)
      expect((updated_article_ids - original_article_ids).length).to eql(6) # just to make sure that we reused the old keys
      expect(article.active_keys.count).to eql(67) # +1 comes from file changes => 2 (addition) - 1 (removal)
      expect(article.translations.count).to eql(213)

      # Manifest
      get :manifest, api_token: project.api_token, name: "support-article", format: :json
      expect(response.status).to eql(400)
      expect(JSON.parse(response.body)).to eql({"error"=>{"errors"=>[{"message"=>"#<Exporter::Article::NotReadyError: Exporter::Article::NotReadyError>"}]}})

      # Assume all translations are done now
      article.reload.translations.where(approved: nil).each do |translation|
        translation.update! copy: "test", approved: true
      end
      article.keys.reload.each(&:recalculate_ready!)

      # Manifest
      get :manifest, api_token: project.api_token, name: "support-article", format: :json
      expect(response.status).to eql(200)
      expect(JSON.parse(response.body)).to eql({ "fr" => { "title" => "test"*3, "header" => "test", "footer" => "test", "main" => "test"*62 } })
    end
  end
end
