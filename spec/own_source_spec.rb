
# OwnSource::FILES is hardcoded (a device may have no filesystem to glob),
# so nothing else notices when a file is added, removed or renamed.
RSpec.describe 'MRDebug::OwnSource::FILES' do
  it "lists exactly this repo's Ruby sources" do
    root = File.expand_path('..', __dir__)
    expected = Dir.chdir(root) do
      Dir.glob(['mrblib/**/*.rb', 'tools/mrdebug/**/*.rb', 'console/mrblib/**/*.rb']).sort
    end
    out = Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'files.rb'), "puts MRDebug::OwnSource::FILES\n")
      stdout, status = Open3.capture2(smoke_bin, 'files.rb', chdir: dir)
      expect(status).to be_success
      stdout
    end
    expect(out.split("\n").sort).to eq(expected)
  end
end
