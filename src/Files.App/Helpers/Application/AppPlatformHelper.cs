// Copyright (c) Files Community
// Licensed under the MIT License.

using System.IO;
using System.Text.Json;

namespace Files.App.Helpers
{
	/// <summary>
	/// Provides platform-agnostic access to app version, paths, and settings
	/// for unpackaged (Win32) mode, replacing ApplicationData.Current and Package.Current.
	/// </summary>
	public static class AppPlatformHelper
	{
		private static readonly string _appName = "FilesDev";
		private static readonly string _appDisplayName = "Files - Dev";
		private static readonly string _appFamilyName = "FilesDev";

		private static readonly Version _appVersion = new(4, 1, 6, 0);

		private static readonly string _localAppDataPath =
			Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Files");

		private static readonly string _roamingAppDataPath =
			Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Files");

		private static readonly string _tempFolderPath =
			Path.Combine(Path.GetTempPath(), "Files");

		private static readonly string _localCacheFolderPath =
			Path.Combine(_localAppDataPath, "Cache");

		private static LocalSettingsStore? _localSettings;

		/// <summary>
		/// Gets the application name (equivalent to Package.Current.Id.Name).
		/// </summary>
		public static string AppName => _appName;

		/// <summary>
		/// Gets the application display name (equivalent to Package.Current.DisplayName).
		/// </summary>
		public static string AppDisplayName => _appDisplayName;

		/// <summary>
		/// Gets the application family name (equivalent to Package.Current.Id.FamilyName).
		/// </summary>
		public static string AppFamilyName => _appFamilyName;

		/// <summary>
		/// Gets the application version (equivalent to Package.Current.Id.Version).
		/// </summary>
		public static Version AppVersion => _appVersion;

		/// <summary>
		/// Gets the installed location path (equivalent to Package.Current.InstalledLocation.Path).
		/// </summary>
		public static string InstalledPath => AppContext.BaseDirectory;

		/// <summary>
		/// Gets the effective path (equivalent to Package.Current.EffectivePath).
		/// </summary>
		public static string EffectivePath => AppContext.BaseDirectory;

		/// <summary>
		/// Gets the local folder path (equivalent to ApplicationData.Current.LocalFolder.Path).
		/// </summary>
		public static string LocalFolderPath
		{
			get
			{
				Directory.CreateDirectory(_localAppDataPath);
				return _localAppDataPath;
			}
		}

		/// <summary>
		/// Gets the roaming folder path (equivalent to ApplicationData.Current.RoamingFolder.Path).
		/// </summary>
		public static string RoamingFolderPath
		{
			get
			{
				Directory.CreateDirectory(_roamingAppDataPath);
				return _roamingAppDataPath;
			}
		}

		/// <summary>
		/// Gets the temporary folder path (equivalent to ApplicationData.Current.TemporaryFolder.Path).
		/// </summary>
		public static string TempFolderPath
		{
			get
			{
				Directory.CreateDirectory(_tempFolderPath);
				return _tempFolderPath;
			}
		}

		/// <summary>
		/// Gets the local cache folder path (equivalent to ApplicationData.Current.LocalCacheFolder.Path).
		/// </summary>
		public static string LocalCacheFolderPath
		{
			get
			{
				Directory.CreateDirectory(_localCacheFolderPath);
				return _localCacheFolderPath;
			}
		}

		/// <summary>
		/// Gets the local settings store (equivalent to ApplicationData.Current.LocalSettings).
		/// </summary>
		public static LocalSettingsStore LocalSettings
		{
			get
			{
				_localSettings ??= new LocalSettingsStore(
					Path.Combine(LocalFolderPath, "local_settings.json"));

				return _localSettings;
			}
		}
	}

	/// <summary>
	/// JSON-backed key-value store that replaces ApplicationData.Current.LocalSettings.
	/// </summary>
	public sealed class LocalSettingsStore
	{
		private readonly string _filePath;
		private readonly object _lock = new();
		private Dictionary<string, JsonElement> _values;

		internal LocalSettingsStore(string filePath)
		{
			_filePath = filePath;
			_values = Load();
		}

		/// <summary>
		/// Gets or sets a value by key.
		/// </summary>
		public object? this[string key]
		{
			get
			{
				lock (_lock)
				{
					return _values.TryGetValue(key, out var value) ? DeserializeValue(value) : null;
				}
			}
			set
			{
				lock (_lock)
				{
					if (value is null)
						_values.Remove(key);
					else
						_values[key] = JsonSerializer.SerializeToElement(value);

					Save();
				}
			}
		}

		/// <summary>
		/// Gets a typed value with a default.
		/// </summary>
		public T Get<T>(string key, T defaultValue)
		{
			lock (_lock)
			{
				if (!_values.TryGetValue(key, out var value))
					return defaultValue;

				try
				{
					return value.Deserialize<T>() ?? defaultValue;
				}
				catch
				{
					return defaultValue;
				}
			}
		}

		/// <summary>
		/// Sets a typed value.
		/// </summary>
		public void Set<T>(string key, T value)
		{
			lock (_lock)
			{
				if (value is null)
					_values.Remove(key);
				else
					_values[key] = JsonSerializer.SerializeToElement(value);

				Save();
			}
		}

		/// <summary>
		/// Checks if a key exists.
		/// </summary>
		public bool ContainsKey(string key)
		{
			lock (_lock)
			{
				return _values.ContainsKey(key);
			}
		}

		/// <summary>
		/// Removes a key.
		/// </summary>
		public void Remove(string key)
		{
			lock (_lock)
			{
				_values.Remove(key);
				Save();
			}
		}

		/// <summary>
		/// Tries to get a value.
		/// </summary>
		public bool TryGetValue(string key, out object? value)
		{
			lock (_lock)
			{
				if (_values.TryGetValue(key, out var element))
				{
					value = DeserializeValue(element);
					return true;
				}

				value = null;
				return false;
			}
		}

		private static object? DeserializeValue(JsonElement element)
		{
			return element.ValueKind switch
			{
				JsonValueKind.String => element.GetString(),
				JsonValueKind.Number => element.TryGetInt32(out var i) ? i : element.GetDouble(),
				JsonValueKind.True => true,
				JsonValueKind.False => false,
				JsonValueKind.Null => null,
				_ => element.GetRawText()
			};
		}

		private Dictionary<string, JsonElement> Load()
		{
			try
			{
				if (File.Exists(_filePath))
				{
					var json = File.ReadAllText(_filePath);
					return JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json) ?? [];
				}
			}
			catch
			{
				// Ignore load errors and start fresh
			}

			return [];
		}

		private void Save()
		{
			try
			{
				var dir = Path.GetDirectoryName(_filePath);
				if (!string.IsNullOrEmpty(dir))
					Directory.CreateDirectory(dir);

				var json = JsonSerializer.Serialize(_values);
				File.WriteAllText(_filePath, json);
			}
			catch
			{
				// Ignore save errors
			}
		}
	}
}
