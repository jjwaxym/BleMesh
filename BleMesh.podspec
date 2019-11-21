Pod::Spec.new do |s|

  s.platform                = :ios
  s.ios.deployment_target   = "11.0"
  s.swift_version           = "5.0"
  s.requires_arc            = true
  s.name                    = "BleMesh"
  s.version                 = "1.0.0"
  s.summary                 = "BleMesh, a mesh over Bluetooth LE"
  s.author                  = { "Jean-Jacques Wacksman" => "jjwacksman-ext@airfrance.fr" }
  s.homepage                = "https://github.com/jjwaxym/BleMesh"
  s.license                 = { :type => "MIT", :file => "MIT_LICENSE" }
  s.source                  = { :git => "https://github.com/jjwaxym/BleMesh.git", :tag => "#{s.version}"}
  s.source_files            = "BleMesh", "BleMesh/**/*.swift"
  s.framework               = "Foundation"
  s.framework               = "CoreBluetooth"

end
