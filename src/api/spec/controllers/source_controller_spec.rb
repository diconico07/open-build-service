RSpec.describe SourceController, :vcr do
  let(:user) { create(:confirmed_user, :with_home, login: 'tom') }
  let(:project) { user.home_project }

  describe 'POST #global_command_orderkiwirepos' do
    it 'is accessible anonymously and forwards backend errors' do
      post :global_command_orderkiwirepos, params: { cmd: 'orderkiwirepos' }
      expect(response).to have_http_status(:bad_request)
      expect(Xmlhash.parse(response.body)['summary']).to eq('read_file: no content attached')
    end
  end

  describe 'POST #global_command_branch' do
    it 'is not accessible anonymously' do
      post :global_command_branch, params: { cmd: 'branch' }
      expect(flash[:error]).to eq('Anonymous user is not allowed here - please login (anonymous_user)')
      expect(response).to redirect_to(root_path)
    end
  end

  describe 'POST #global_command_createmaintenanceincident' do
    it 'is not accessible anonymously' do
      post :global_command_createmaintenanceincident, params: { cmd: 'createmaintenanceincident' }
      expect(flash[:error]).to eq('Anonymous user is not allowed here - please login (anonymous_user)')
      expect(response).to redirect_to(root_path)
    end
  end

  describe 'POST #package_command_release' do
    subject { post :package_command, params: { cmd: 'release', project: project, package: package }, format: :xml }

    let(:user) { create(:confirmed_user, login: 'peter') }
    let(:target_project) do
      released_project = create(:project, name: 'franz_released', maintainer: user)
      create(:repository, project: released_project, name: 'standard', architectures: ['x86_64'])

      released_project.store
      released_project
    end

    let(:project) do
      source_project = create(:project, name: 'franz', maintainer: user)
      create(:repository, project: source_project, name: 'standard', architectures: ['x86_64'])
      create(:release_target, repository: source_project.repositories.first, target_repository: target_project.repositories.first, trigger: 'manual')

      source_project.store
      source_project
    end
    let(:package) { create(:package, name: 'hans', project: project) }

    before do
      login user
    end

    it { expect(subject).to have_http_status(:ok) }
    it { expect { subject }.to change(Package, :count).from(0).to(2) }

    context 'without project' do
      let(:project) { 'franz' }
      let(:package) { 'hans' }

      it { expect(subject.headers['X-Opensuse-Errorcode']).to eql('unknown_project') }
    end

    context 'without package' do
      let(:package) { 'hans' }

      it { expect(subject.headers['X-Opensuse-Errorcode']).to eql('unknown_package') }
    end

    context 'without release targets' do
      let(:project) { create(:project, maintainer: user) }

      it { expect(subject.headers['X-Opensuse-Errorcode']).to eql('no_matching_release_target') }
    end

    context 'with target parameters' do
      subject do
        post :package_command,
             params: { cmd: 'release',
                       package: package,
                       project: project,
                       target_project: target_project.name,
                       target_repository: target_project.repositories.first.name,
                       repository: project.repositories.first.name }, format: :xml
      end

      it { expect(subject).to have_http_status(:ok) }
      it { expect { subject }.to change(Package, :count).from(0).to(2) }
    end

    context 'with scmsync project' do
      let(:project) do
        source_project = create(:project, name: 'franz', scmsync: 'https://github.com/hennevogel/scmsync-project.git', maintainer: user)
        create(:repository, project: source_project, name: 'standard', architectures: ['x86_64'])
        create(:release_target, repository: source_project.repositories.first, target_repository: target_project.repositories.first, trigger: 'manual')

        source_project.store
        source_project
      end

      let(:package) { 'hans' }
      let(:package_xml) do
        <<-HEREDOC
          <package name="hans" project="#{project.name}">
            <title>hans</title>
            <description>franz</description>
          </package>
        HEREDOC
      end

      before do
        allow(Backend::Api::Sources::Package).to receive(:meta).and_return(package_xml)
      end

      it { expect(subject).to have_http_status(:ok) }
      it { expect { subject }.to change(Package, :count).from(0).to(1) }
    end
  end

  describe 'POST #package_command' do
    let(:multibuild_package) { create(:package, name: 'multibuild') }
    let(:multibuild_project) { multibuild_package.project }
    let(:repository) { create(:repository) }
    let(:target_repository) { create(:repository) }

    before do
      multibuild_project.repositories << repository
      project.repositories << target_repository
      login user
    end

    context "with 'diff' command for a multibuild package" do
      before do
        post :package_command, params: {
          cmd: 'diff', package: "#{multibuild_package.name}:one", project: multibuild_project, target_project: project
        }
      end

      it { expect(flash[:error]).to eq("invalid package name '#{multibuild_package.name}:one' (invalid_package_name)") }
      it { expect(response).to have_http_status(:found) }
    end
  end

  describe 'POST #package_command_undelete' do
    context 'when not having permissions on the deleted package' do
      let(:package) { create(:package) }

      before do
        package.destroy
        login user

        post :package_command, params: {
          cmd: 'undelete', project: package.project, package: package
        }
      end

      it { expect(response).to have_http_status(:found) }
      it { expect(flash[:error]).to have_text('no permission to create package') }
    end

    context 'when having permissions on the deleted package' do
      let(:package) { create(:package, name: 'some_package', project: project) }

      before do
        package.destroy
        login user

        post :package_command, params: {
          cmd: 'undelete', project: package.project, package: package
        }
      end

      it { expect(response).to have_http_status(:ok) }
    end

    context 'when not having permissions to set the time' do
      let(:package) { create(:package, project: project) }

      before do
        package.destroy
        login user

        post :package_command, params: {
          cmd: 'undelete', project: package.project, package: package, time: 1.month.ago
        }
      end

      it { expect(response).to have_http_status(:found) }
      it { expect(flash[:error]).to have_text('Only administrators are allowed to set the time') }
    end

    context 'when having permissions to set the time' do
      let(:admin) { create(:admin_user, login: 'admin') }
      let(:package) { create(:package, name: 'some_package', project: project) }
      let(:future) { 4_803_029_439 }

      before do
        package.destroy
        login admin

        post :package_command, params: {
          cmd: 'undelete', project: package.project, package: package, time: future
        }
      end

      it { expect(response).to have_http_status(:ok) }
    end
  end
end
