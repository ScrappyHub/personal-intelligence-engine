const certificateFile = process.env.PIE_WINDOWS_CERTIFICATE_FILE || '';
const certificatePassword = process.env.PIE_WINDOWS_CERTIFICATE_PASSWORD || '';
if (Boolean(certificateFile) !== Boolean(certificatePassword)) {
  throw new Error('PIE_DESKTOP_SIGNING_CONFIGURATION_INCOMPLETE');
}

const squirrelConfig = { name: 'pie_desktop', setupExe: 'PIE-Setup.exe', noMsi: true };
if (certificateFile) {
  squirrelConfig.certificateFile = certificateFile;
  squirrelConfig.certificatePassword = certificatePassword;
}

module.exports = {
  outDir: 'release',
  packagerConfig: {
    asar: true,
    executableName: 'PIE',
    extraResource: ['runtime'],
  },
  rebuildConfig: {},
  makers: [
    {
      name: '@electron-forge/maker-squirrel',
      config: squirrelConfig,
    },
  ],
};
