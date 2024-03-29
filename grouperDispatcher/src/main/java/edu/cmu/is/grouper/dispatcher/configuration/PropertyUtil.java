/*Copyright 2014 Carnegie Mellon University
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.*/


/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package edu.cmu.is.grouper.dispatcher.configuration;

import java.io.FileInputStream;
import java.util.Properties;

import org.apache.log4j.Logger;

/**
 * 
 * @author hrf
 */
public class PropertyUtil {

	public static final String PROPERTIES_DIR_PATH = "/opt/grouperDispatcher/conf/";

	public static final String PROPERTIES_FILE_NAME = "grouperDispatcher.properties";

	private static Properties properties = new Properties();

	protected static Logger staticLogger = Logger.getLogger(PropertyUtil.class);

	private static Long ONE_HOUR = 60L * 60L * 1000L;

	private static Long lastRefresh;

	private static synchronized void clearPropertiesIfTime() {
		if (lastRefresh == null) {
			lastRefresh = System.currentTimeMillis();
		} else {
			Long timeSinceLastRefresh = System.currentTimeMillis() - lastRefresh;
			// staticLogger.info("time since last refresh: " + timeSinceLastRefresh + "  ? is > " + Constants.ONE_HOUR);
			if (timeSinceLastRefresh > ONE_HOUR) {
				// cause to reload all the bakery urls
				lastRefresh = System.currentTimeMillis();
				properties = new Properties();
				staticLogger.info("Going to reload properties as has been more than 1 hour");
			}
		}
	}

	public static synchronized String getProp(String s) {
		clearPropertiesIfTime();
		if (properties.isEmpty()) {
			loadProperties();
		}
		String value = (String) properties.get(s);
		// staticLogger.info("Property: " + s + "    value: " + value);
		return value;
	}

	public static String getProp(String s, String defaultProp) {
		String prop = PropertyUtil.getProp(s);
		if (prop == null) {
			return defaultProp;
		} else {
			// staticLogger.fine("returning prop: " + prop + "  for key: " + s);
			return prop;
		}
	}

	private static synchronized void loadProperties() {
		// Read properties file.
		try {
			staticLogger.info("*** going to load properties from " + PROPERTIES_DIR_PATH + PROPERTIES_FILE_NAME + " ***");
			properties.load(new FileInputStream(PROPERTIES_DIR_PATH + PROPERTIES_FILE_NAME));
			staticLogger.info("properties read OKay from file: " + PROPERTIES_DIR_PATH + PROPERTIES_FILE_NAME);
		} catch (Exception e) {
			staticLogger.error("Problem loading properties or initializing webapp - loading  " + PROPERTIES_FILE_NAME, e);
			System.out.println("Problem loading properties or initializing webapp - loading  " + PROPERTIES_FILE_NAME);
		}
	}
}
