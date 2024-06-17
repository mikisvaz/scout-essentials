# Generated by juwelier
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Juwelier::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: scout-essentials 1.6.1 ruby lib

Gem::Specification.new do |s|
  s.name = "scout-essentials".freeze
  s.version = "1.6.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Miguel Vazquez".freeze]
  s.date = "2024-06-17"
  s.description = "Things a scout can use anywhere".freeze
  s.email = "mikisvaz@gmail.com".freeze
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.rdoc"
  ]
  s.files = [
    ".document",
    ".vimproject",
    "Gemfile",
    "LICENSE.txt",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "lib/scout-essentials.rb",
    "lib/scout/annotation.rb",
    "lib/scout/annotation/annotated_object.rb",
    "lib/scout/annotation/annotation_module.rb",
    "lib/scout/annotation/array.rb",
    "lib/scout/cmd.rb",
    "lib/scout/concurrent_stream.rb",
    "lib/scout/config.rb",
    "lib/scout/exceptions.rb",
    "lib/scout/indiferent_hash.rb",
    "lib/scout/indiferent_hash/case_insensitive.rb",
    "lib/scout/indiferent_hash/options.rb",
    "lib/scout/log.rb",
    "lib/scout/log/color.rb",
    "lib/scout/log/color_class.rb",
    "lib/scout/log/fingerprint.rb",
    "lib/scout/log/progress.rb",
    "lib/scout/log/progress/report.rb",
    "lib/scout/log/progress/util.rb",
    "lib/scout/log/trap.rb",
    "lib/scout/misc.rb",
    "lib/scout/misc/digest.rb",
    "lib/scout/misc/filesystem.rb",
    "lib/scout/misc/format.rb",
    "lib/scout/misc/helper.rb",
    "lib/scout/misc/insist.rb",
    "lib/scout/misc/math.rb",
    "lib/scout/misc/monitor.rb",
    "lib/scout/misc/system.rb",
    "lib/scout/named_array.rb",
    "lib/scout/open.rb",
    "lib/scout/open/lock.rb",
    "lib/scout/open/lock/lockfile.rb",
    "lib/scout/open/remote.rb",
    "lib/scout/open/stream.rb",
    "lib/scout/open/util.rb",
    "lib/scout/path.rb",
    "lib/scout/path/find.rb",
    "lib/scout/path/tmpfile.rb",
    "lib/scout/path/util.rb",
    "lib/scout/persist.rb",
    "lib/scout/persist/open.rb",
    "lib/scout/persist/path.rb",
    "lib/scout/persist/serialize.rb",
    "lib/scout/resource.rb",
    "lib/scout/resource/open.rb",
    "lib/scout/resource/path.rb",
    "lib/scout/resource/produce.rb",
    "lib/scout/resource/produce/rake.rb",
    "lib/scout/resource/scout.rb",
    "lib/scout/resource/software.rb",
    "lib/scout/resource/util.rb",
    "lib/scout/simple_opt.rb",
    "lib/scout/simple_opt/accessor.rb",
    "lib/scout/simple_opt/doc.rb",
    "lib/scout/simple_opt/get.rb",
    "lib/scout/simple_opt/parse.rb",
    "lib/scout/simple_opt/setup.rb",
    "lib/scout/tmpfile.rb",
    "scout-essentials.gemspec",
    "share/color/color_names",
    "share/color/diverging_colors.hex",
    "share/software/install_helpers",
    "test/scout/annotation/test_annotated_object.rb",
    "test/scout/annotation/test_array.rb",
    "test/scout/indiferent_hash/test_case_insensitive.rb",
    "test/scout/indiferent_hash/test_options.rb",
    "test/scout/log/test_color.rb",
    "test/scout/log/test_fingerprint.rb",
    "test/scout/log/test_progress.rb",
    "test/scout/misc/test_digest.rb",
    "test/scout/misc/test_filesystem.rb",
    "test/scout/misc/test_helper.rb",
    "test/scout/misc/test_insist.rb",
    "test/scout/misc/test_math.rb",
    "test/scout/misc/test_system.rb",
    "test/scout/open/test_lock.rb",
    "test/scout/open/test_remote.rb",
    "test/scout/open/test_stream.rb",
    "test/scout/open/test_util.rb",
    "test/scout/path/test_find.rb",
    "test/scout/path/test_util.rb",
    "test/scout/persist/test_open.rb",
    "test/scout/persist/test_path.rb",
    "test/scout/persist/test_serialize.rb",
    "test/scout/resource/test_path.rb",
    "test/scout/resource/test_produce.rb",
    "test/scout/resource/test_software.rb",
    "test/scout/resource/test_util.rb",
    "test/scout/simple_opt/test_doc.rb",
    "test/scout/simple_opt/test_get.rb",
    "test/scout/simple_opt/test_parse.rb",
    "test/scout/simple_opt/test_setup.rb",
    "test/scout/test_annotation.rb",
    "test/scout/test_cmd.rb",
    "test/scout/test_concurrent_stream.rb",
    "test/scout/test_config.rb",
    "test/scout/test_indiferent_hash.rb",
    "test/scout/test_log.rb",
    "test/scout/test_misc.rb",
    "test/scout/test_named_array.rb",
    "test/scout/test_open.rb",
    "test/scout/test_path.rb",
    "test/scout/test_persist.rb",
    "test/scout/test_resource.rb",
    "test/scout/test_tmpfile.rb",
    "test/test_helper.rb"
  ]
  s.homepage = "http://github.com/mikisvaz/scout-essentials".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.5.10".freeze
  s.summary = "Scout essential tools".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<shoulda>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rdoc>.freeze, ["~> 3.12".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 1.0".freeze])
  s.add_development_dependency(%q<juwelier>.freeze, ["~> 2.1.0".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<term-ansicolor>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<yaml>.freeze, [">= 0".freeze])
end

