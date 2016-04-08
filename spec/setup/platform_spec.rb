require 'setup/platform'

module Setup

RSpec.describe Platform do
  describe '#get_config_value' do
    it 'should get raw values' do
      expect(Platform.get_config_value(12, ['a'])).to eq(12)
      expect(Platform.get_config_value('str', ['a'])).to eq('str')
    end

    it 'should get dictionaries' do
      config = { a: 12 }
      expect(Platform.get_config_value(config, ['a'])).to eq(config)
    end

    it 'should return label results' do
      example_dict = { '<a>' => 12, '<b>' => 15 }
      expect(Platform.get_config_value(example_dict, ['<a>'])).to eq(12)
      expect(Platform.get_config_value(example_dict, ['<b>'])).to eq(15)
      expect(Platform.get_config_value(example_dict, ['<c>'])).to eq(nil)
    end

    it 'should not expand results recursively' do
      value = { '<a>' => 12 }
      example_dict = { '<a>' => value }
      expect(Platform.get_config_value(example_dict, ['<a>'])).to eq(value)
    end
  end

  describe '#machine_labels' do
    it { expect(Platform.machine_labels 'mswin').to eq(['<win>']) }
    it { expect(Platform.machine_labels 'mingw').to eq(['<win>']) }
    it { expect(Platform.machine_labels 'bccwin').to eq(['<win>']) }
    it { expect(Platform.machine_labels 'wince').to eq(['<win>']) }
    it { expect(Platform.machine_labels 'emx').to eq(['<win>']) }
    it { expect(Platform.machine_labels 'cygwin').to eq(['<win>']) }
    it { expect(Platform.machine_labels 'x86_64-darwin14').to eq(['<unix>', '<osx>', '<mac>']) }
    it { expect(Platform.machine_labels 'ubuntu').to eq(['<unix>', '<linux>']) }
  end
end

end # module Setup