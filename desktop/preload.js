'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('pieDesktop', Object.freeze({
  chooseRepository: () => ipcRenderer.invoke('pie:choose-repository'),
  chooseSessionBackup: () => ipcRenderer.invoke('pie:choose-session-backup'),
  listRepositories: () => ipcRenderer.invoke('pie:list-repositories'),
  platform: process.platform,
}));
