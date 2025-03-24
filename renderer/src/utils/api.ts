interface ApiResponse<T = any> {
  data: T;
  success: boolean;
  error?: string;
}

export async function fetchApi<T = any>(
  url: string,
  options: RequestInit = {}
): Promise<ApiResponse<T>> {
  try {
    const defaultHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    const response = await fetch(url, {
      ...options,
      headers: {
        ...defaultHeaders,
        ...options.headers,
      },
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || `HTTP error! status: ${response.status}`);
    }

    return {
      data,
      success: true,
    };
  } catch (error) {
    console.error('API call failed:', error);
    return {
      data: null as T,
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error occurred',
    };
  }
} 